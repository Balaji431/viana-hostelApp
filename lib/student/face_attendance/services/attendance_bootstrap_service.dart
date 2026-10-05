import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/api_service.dart';
import 'device_security_service.dart';

class AttendancePolicy {
  final bool attendanceEnabled;
  final bool configuredEmpOnly;
  final bool isConfigured;
  final bool geoEnforce;
  final bool showGeofence;
  final bool allowGeo;
  final bool isIpBased;
  final double geoMaxAccuracyMeters;

  const AttendancePolicy({
    this.attendanceEnabled = true,
    this.configuredEmpOnly = false,
    this.isConfigured = true,
    this.geoEnforce = true,
    this.showGeofence = true,
    this.allowGeo = true,
    this.isIpBased = true,
    this.geoMaxAccuracyMeters = 50.0,
  });

  factory AttendancePolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AttendancePolicy();
    return AttendancePolicy(
      attendanceEnabled: json['attendance_enabled'] ?? true,
      configuredEmpOnly: json['configured_emp_only'] ?? false,
      isConfigured: json['is_configured'] ?? true,
      geoEnforce: json['geo_enforce'] ?? true,
      showGeofence: json['show_geofence'] ?? true,
      allowGeo: json['allow_geo'] ?? true,
      isIpBased: json['is_ip_based'] ?? true,
      geoMaxAccuracyMeters: (json['geo_max_accuracy_meters'] as num?)?.toDouble() ?? 50.0,
    );
  }
}

class AttendanceAuthSession {
  final String accessToken;
  final int expiresIn;
  final String tokenType;
  final bool faceEnrolled;
  final int bioId;
  final AttendancePolicy policy;
  final Map<String, dynamic>? employee;
  final Map<String, dynamic>? device;

  const AttendanceAuthSession({
    required this.accessToken,
    required this.expiresIn,
    required this.tokenType,
    required this.faceEnrolled,
    required this.bioId,
    required this.policy,
    this.employee,
    this.device,
  });

  factory AttendanceAuthSession.fromJson(Map<String, dynamic> json, int fallbackBioId) {
    final data = json['data'] ?? json;
    return AttendanceAuthSession(
      accessToken: data['access_token'] ?? '',
      expiresIn: data['expires_in'] ?? 3600,
      tokenType: data['token_type'] ?? 'Bearer',
      faceEnrolled: data['face_enrolled'] ?? false,
      bioId: (data['employee']?['bio_id'] as num?)?.toInt() ?? fallbackBioId,
      policy: AttendancePolicy.fromJson(data['policy']),
      employee: data['employee'] as Map<String, dynamic>?,
      device: data['device'] as Map<String, dynamic>?,
    );
  }
}

class AttendanceBootstrapService {
  final String baseUrl;
  final http.Client _client;

  AttendanceBootstrapService({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? ApiService.attendanceServerUrl).replaceAll(RegExp(r'/api/?$'), ''),
        _client = client ?? http.Client();

  /// 1. Synchronize server time and check clock skew
  Future<int> checkServerTime() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/time');
      final res = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final epochMs = (json['data']?['epoch_ms'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        final maxSkew = (json['data']?['max_clock_skew_seconds'] as num?)?.toInt() ?? 120;
        final clientNow = DateTime.now().millisecondsSinceEpoch;
        final skewSeconds = ((clientNow - epochMs).abs() / 1000).round();
        if (skewSeconds > maxSkew) {
          throw Exception('CLOCK_SKEW: Please enable automatic network time in device settings.');
        }
        return epochMs;
      }
    } catch (e) {
      if (e.toString().contains('CLOCK_SKEW')) rethrow;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// 2. Validate employee & device identity, return JWT session
  Future<AttendanceAuthSession> validateDeviceAndAuth({
    required int bioId,
    required NativeDeviceEvidence evidence,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/auth/validate');
    final payload = evidence.toBootstrapPayload(bioId: bioId);

    try {
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200 && (json['success'] == true || json['status'] == 'ok')) {
        return AttendanceAuthSession.fromJson(json, bioId);
      }
      final code = json['error']?['code'] ?? json['code'] ?? 'AUTH_FAILED';
      final message = json['error']?['message'] ?? json['message'] ?? 'Device validation failed';
      throw Exception('$code: $message');
    } catch (e) {
      if (e is Exception && e.toString().contains('AUTH_FAILED')) rethrow;
      throw Exception(
        'ATTENDANCE_SERVER_UNREACHABLE: Cannot connect to server at $baseUrl.\n'
        'Check server connection. The server must be online and reachable.',
      );
    }
  }

  /// 3. Fetch runtime policy
  Future<AttendancePolicy> fetchPolicy(String accessToken) async {
    final uri = Uri.parse('$baseUrl/api/v1/attendance/policy');
    final res = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 6));

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      return AttendancePolicy.fromJson(json['data'] ?? json);
    }
    return const AttendancePolicy();
  }

  /// 4. Geofence preflight hint (UI hint only)
  Future<Map<String, dynamic>> checkGeofenceHint({
    required double latitude,
    required double longitude,
    required double accuracy,
    required int bioId,
    required String accessToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/attendance/geofence/status?latitude=$latitude&longitude=$longitude&accuracy=$accuracy&bio_id=$bioId');
    try {
      final res = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['data'] ?? {};
      }
    } catch (_) {}
    return {'is_within_geofence': true};
  }

  /// 5. HTTP Fast-Punch compatibility fallback
  Future<Map<String, dynamic>> httpFastPunch({
    required String accessToken,
    required Map<String, dynamic> punchPayload,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/attendance/fast-punch');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(punchPayload),
    ).timeout(const Duration(seconds: 15));

    final json = jsonDecode(res.body);
    if (res.statusCode == 200 && (json['success'] == true || json['status'] == 'ok')) {
      return json;
    }
    final code = json['error']?['code'] ?? json['code'] ?? 'PUNCH_FAILED';
    final message = json['error']?['message'] ?? json['message'] ?? 'Attendance submission failed';
    throw Exception('$code: $message');
  }
}
