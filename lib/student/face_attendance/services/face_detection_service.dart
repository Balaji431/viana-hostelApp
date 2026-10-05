import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_attendance_models.dart';

/// Callback type for status and metric updates
typedef OnFaceStatusChanged = void Function(
  FaceAttendanceStatus status,
  FaceDetectionMetrics metrics,
);

/// Service handling front camera lifecycle and real ML face detection.
class FaceDetectionService {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _currentCamera;
  CameraLensDirection _preferredLens = CameraLensDirection.front;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isSimulated = false;

  // ML Kit face detector — only created on Android/iOS
  FaceDetector? _faceDetector;

  // Frame processing guard — prevents overlapping ML Kit calls
  bool _isProcessingFrame = false;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

  // How often to run face detection (ms)
  static const int _frameThrottleMs = 300;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;
  bool get isSimulated => _isSimulated;
  CameraLensDirection get preferredLens => _preferredLens;
  CameraDescription? get currentCamera => _currentCamera;
  bool get isBackCamera => (_currentCamera?.lensDirection ?? _preferredLens) == CameraLensDirection.back;

  /// True when real ML Kit detection is supported on this platform
  static bool get _mlKitSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // ---------------------------------------------------------------------------
  // Initialize
  // ---------------------------------------------------------------------------

  /// Initialize camera (front or rear) and begin detection
  Future<bool> initialize({
    required OnFaceStatusChanged onStatusChanged,
    CameraLensDirection preferredLens = CameraLensDirection.front,
  }) async {
    _isDisposed = false;
    _preferredLens = preferredLens;
    onStatusChanged(FaceAttendanceStatus.initializing, FaceDetectionMetrics.initial);

    // Build ML Kit detector on supported platforms
    if (_mlKitSupported) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,  // gives leftEyeOpenProbability, rightEyeOpenProbability
          enableLandmarks: false,
          enableContours: false,
          enableTracking: false,
          minFaceSize: 0.15,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    }

    try {
      _availableCameras = await availableCameras();

      if (_availableCameras.isEmpty) {
        _emitNoCamera(onStatusChanged);
        return false;
      }

      // Find camera matching preferredLens; fall back to first available
      final selectedCamera = _availableCameras.firstWhere(
        (cam) => cam.lensDirection == preferredLens,
        orElse: () => _availableCameras.first,
      );
      _currentCamera = selectedCamera;

      final newController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: _mlKitSupported
            ? (Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888)
            : ImageFormatGroup.jpeg,
      );

      await newController.initialize();

      if (_isDisposed) {
        await newController.dispose();
        return false;
      }

      _controller = newController;
      _isInitialized = true;

      if (_mlKitSupported) {
        _isSimulated = false;
        _startMlKitStream(onStatusChanged);
      } else {
        _isSimulated = true;
        onStatusChanged(FaceAttendanceStatus.cameraReady, FaceDetectionMetrics.searching);
      }

      return true;
    } on CameraException catch (e) {
      debugPrint('FaceDetectionService CameraException: ${e.code} ${e.description}');
      if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessRestricted') {
        onStatusChanged(FaceAttendanceStatus.permissionDenied, FaceDetectionMetrics.initial);
      } else if (e.code == 'CameraAccessDeniedWithoutPrompt') {
        onStatusChanged(FaceAttendanceStatus.permissionPermanentlyDenied, FaceDetectionMetrics.initial);
      } else {
        _emitNoCamera(onStatusChanged);
      }
      return false;
    } catch (e) {
      debugPrint('FaceDetectionService error: $e');
      _emitNoCamera(onStatusChanged);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // ML Kit image-stream pipeline
  // ---------------------------------------------------------------------------

  void _startMlKitStream(OnFaceStatusChanged onStatusChanged) {
    onStatusChanged(FaceAttendanceStatus.cameraReady, FaceDetectionMetrics.searching);

    _controller?.startImageStream((CameraImage image) async {
      if (_isDisposed || _isProcessingFrame) return;

      final now = DateTime.now();
      if (now.difference(_lastAnalysis).inMilliseconds < _frameThrottleMs) return;

      _isProcessingFrame = true;
      _lastAnalysis = now;

      try {
        await _processFrame(image, onStatusChanged);
      } catch (e) {
        debugPrint('FaceDetectionService frame error: $e');
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _processFrame(
    CameraImage image,
    OnFaceStatusChanged onStatusChanged,
  ) async {
    if (_faceDetector == null || _controller == null) return;

    final inputImage = _buildInputImage(image);
    if (inputImage == null) return;

    final List<Face> faces = await _faceDetector!.processImage(inputImage);
    if (_isDisposed) return;

    final (status, metrics) = _evaluateFaces(faces, image);
    onStatusChanged(status, metrics);
  }

  /// Convert CameraImage → InputImage for ML Kit
  InputImage? _buildInputImage(CameraImage image) {
    try {
      final camera = _currentCamera ?? _availableCameras.firstWhere(
        (cam) => cam.lensDirection == _preferredLens,
        orElse: () => _availableCameras.first,
      );

      InputImageRotation rotation;
      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation)
            ?? InputImageRotation.rotation0deg;
      } else {
        final orientations = {
          DeviceOrientation.portraitUp: 0,
          DeviceOrientation.landscapeLeft: 90,
          DeviceOrientation.portraitDown: 180,
          DeviceOrientation.landscapeRight: 270,
        };
        final deviceOrientation =
            _controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp;
        int comp = orientations[deviceOrientation] ?? 0;
        if (camera.lensDirection == CameraLensDirection.front) {
          comp = (camera.sensorOrientation + comp) % 360;
        } else {
          comp = (camera.sensorOrientation - comp + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(comp)
            ?? InputImageRotation.rotation0deg;
      }

      final format = InputImageFormatValue.fromRawValue(image.format.raw)
          ?? (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);

      Uint8List bytes;
      if (image.planes.length == 1) {
        bytes = image.planes.first.bytes;
      } else {
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Error building InputImage: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Face evaluation logic
  // ---------------------------------------------------------------------------

  /// Evaluate detected faces and return status + metrics (including raw face data for liveness)
  (FaceAttendanceStatus, FaceDetectionMetrics) _evaluateFaces(
    List<Face> faces,
    CameraImage image,
  ) {
    if (faces.isEmpty) {
      return (FaceAttendanceStatus.noFace, const FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.bad, faceStatusText: 'No face',
        positionLevel: MetricLevel.pending, positionText: 'N/A',
        lightingLevel: MetricLevel.pending, lightingText: 'N/A',
        distanceLevel: MetricLevel.pending, distanceText: 'N/A',
        faceCount: 0,
      ));
    }

    if (faces.length > 1) {
      return (FaceAttendanceStatus.multipleFaces, FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.bad,
        faceStatusText: '${faces.length} faces',
        positionLevel: MetricLevel.pending, positionText: 'N/A',
        lightingLevel: MetricLevel.good, lightingText: 'Good',
        distanceLevel: MetricLevel.pending, distanceText: 'N/A',
        faceCount: faces.length,
      ));
    }

    final face = faces.first;
    final bbox = face.boundingBox;

    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    final faceArea = (bbox.width * bbox.height).abs();
    final totalArea = imgW * imgH;
    final coverage = totalArea > 0 ? (faceArea / totalArea) : 0.0;

    final faceCenterX = bbox.center.dx;
    final faceCenterY = bbox.center.dy;
    final imgCenterX = imgW / 2;
    final imgCenterY = imgH / 2;
    final offsetX = (faceCenterX - imgCenterX).abs() / imgW;
    final offsetY = (faceCenterY - imgCenterY).abs() / imgH;

    final brightness = _estimateBrightness(image);

    MetricLevel distLevel;
    String distText;
    if (coverage < 0.08) {
      distLevel = MetricLevel.warn;
      distText = 'Too far';
    } else if (coverage > 0.65) {
      distLevel = MetricLevel.warn;
      distText = 'Too close';
    } else {
      distLevel = MetricLevel.good;
      distText = 'Optimal';
    }

    MetricLevel posLevel;
    String posText;
    if (offsetX > 0.28 || offsetY > 0.28) {
      posLevel = MetricLevel.warn;
      posText = 'Off-center';
    } else {
      posLevel = MetricLevel.good;
      posText = 'Centered';
    }

    MetricLevel lightLevel;
    String lightText;
    if (brightness < 45.0) {
      lightLevel = MetricLevel.bad;
      lightText = 'Too dark';
    } else {
      lightLevel = MetricLevel.good;
      lightText = 'Good';
    }

    final double? headEulerY = face.headEulerAngleY;
    final double? leftEyeOpen = face.leftEyeOpenProbability;
    final double? rightEyeOpen = face.rightEyeOpenProbability;

    final metrics = FaceDetectionMetrics(
      faceStatusLevel: MetricLevel.good,
      faceStatusText: '1 face',
      positionLevel: posLevel,
      positionText: posText,
      lightingLevel: lightLevel,
      lightingText: lightText,
      distanceLevel: distLevel,
      distanceText: distText,
      faceCount: 1,
      faceRect: bbox,
      brightness: brightness,
      headEulerY: headEulerY,
      leftEyeOpenProbability: leftEyeOpen,
      rightEyeOpenProbability: rightEyeOpen,
    );

    if (lightLevel == MetricLevel.bad) {
      return (FaceAttendanceStatus.poorLighting, metrics);
    }
    if (distLevel == MetricLevel.warn) {
      return (coverage < 0.08 ? FaceAttendanceStatus.tooFar : FaceAttendanceStatus.tooClose, metrics);
    }
    if (posLevel == MetricLevel.warn) {
      return (FaceAttendanceStatus.outOfFrame, metrics);
    }

    return (FaceAttendanceStatus.positioned, metrics);
  }

  double _estimateBrightness(CameraImage image) {
    try {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      if (bytes.isEmpty) return 128.0;

      int total = 0;
      final step = (bytes.length / 50).floor().clamp(1, bytes.length);
      int count = 0;
      for (int i = 0; i < bytes.length; i += step) {
        total += bytes[i];
        count++;
      }
      return count > 0 ? (total / count) : 128.0;
    } catch (_) {
      return 128.0;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void _emitNoCamera(OnFaceStatusChanged onStatusChanged) {
    onStatusChanged(
      FaceAttendanceStatus.noFace,
      const FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.bad,
        faceStatusText: 'No camera',
        positionLevel: MetricLevel.pending, positionText: 'N/A',
        lightingLevel: MetricLevel.pending, lightingText: 'N/A',
        distanceLevel: MetricLevel.pending, distanceText: 'N/A',
        faceCount: 0,
      ),
    );
  }

  /// Pause camera stream on app backgrounding
  Future<void> pause() async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (_mlKitSupported && _controller!.value.isStreamingImages) {
          await _controller?.stopImageStream();
        }
        await _controller?.pausePreview();
      } catch (_) {}
    }
  }

  /// Resume camera on app foregrounding
  Future<void> resume({required OnFaceStatusChanged onStatusChanged}) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller?.resumePreview();
        if (_mlKitSupported) {
          _startMlKitStream(onStatusChanged);
        } else {
          onStatusChanged(FaceAttendanceStatus.cameraReady, FaceDetectionMetrics.searching);
        }
      } catch (_) {
        _emitNoCamera(onStatusChanged);
      }
    } else {
      await initialize(onStatusChanged: onStatusChanged);
    }
  }

  /// Capture a real JPEG frame as data URL for server verification/liveness
  Future<String?> captureFrameBase64() async {
    if (_controller == null || !_controller!.value.isInitialized) return null;
    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } catch (e) {
      debugPrint('captureFrameBase64 error: $e');
      return null;
    }
  }

  /// Cleanly dispose camera and ML Kit resources
  void dispose() {
    _isDisposed = true;
    _isProcessingFrame = false;

    try {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          _mlKitSupported &&
          _controller!.value.isStreamingImages) {
        _controller?.stopImageStream();
      }
    } catch (_) {}

    _faceDetector?.close();
    _faceDetector = null;

    final c = _controller;
    _controller = null;
    _isInitialized = false;
    c?.dispose();
  }
}
