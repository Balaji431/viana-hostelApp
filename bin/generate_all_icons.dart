import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

img.Image createCircularEmblem(img.Image logo, int size) {
  final result = img.Image(width: size, height: size, numChannels: 4);
  final double center = size / 2.0;
  final double radius = (size / 2.0) - 1.0;
  final double rSquared = radius * radius;

  // 1. Draw solid white anti-aliased circular disk
  for (int y = 0; y < size; y++) {
    final double dy = y + 0.5 - center;
    for (int x = 0; x < size; x++) {
      final double dx = x + 0.5 - center;
      final double distSq = dx * dx + dy * dy;
      if (distSq <= rSquared) {
        result.setPixelRgba(x, y, 255, 255, 255, 255);
      } else if (distSq <= (radius + 1.0) * (radius + 1.0)) {
        final double alpha = (radius + 1.0 - sqrt(distSq)).clamp(0.0, 1.0);
        result.setPixelRgba(x, y, 255, 255, 255, (alpha * 255).round());
      } else {
        result.setPixelRgba(x, y, 0, 0, 0, 0); // 100% transparent outside circle
      }
    }
  }

  // 2. Scale logo to fit inside circular white badge (72% diameter)
  final int logoDim = (size * 0.72).round();
  final scaledLogo = img.copyResize(logo, width: logoDim, height: logoDim, interpolation: img.Interpolation.cubic);
  final int ox = ((size - logoDim) / 2.0).round();
  final int oy = ((size - logoDim) / 2.0).round();

  // 3. Composite logo cleanly within circular bounds
  for (int y = 0; y < logoDim; y++) {
    final int dstY = y + oy;
    final double dy = dstY + 0.5 - center;
    for (int x = 0; x < logoDim; x++) {
      final int dstX = x + ox;
      final double dx = dstX + 0.5 - center;
      if (dx * dx + dy * dy <= rSquared) {
        final p = scaledLogo.getPixel(x, y);
        if (p.a > 0 && !(p.r > 245 && p.g > 245 && p.b > 245)) {
          result.setPixel(dstX, dstY, p);
        }
      }
    }
  }

  return result;
}

void main() {
  final masterPath = 'android/playstore-icon.png';
  final masterFile = File(masterPath);

  print('========================================================');
  print('  GLOBAL LOGO PROCESSOR - MASTER BRAND ASSET REPLICATION');
  print('========================================================\n');

  if (!masterFile.existsSync()) {
    print('[ERROR] Master image not found at $masterPath');
    return;
  }

  print('Reading master image from $masterPath...');
  final bytes = masterFile.readAsBytesSync();
  final master = img.decodeImage(bytes);

  if (master == null) {
    print('[ERROR] Could not decode master image.');
    return;
  }

  print('Master image successfully loaded: ${master.width}x${master.height} px\n');

  // Maintain complete symmetry: place the full uncropped master image directly onto a transparent square canvas
  final int maxDim = master.width > master.height ? master.width : master.height;
  final int targetSquareSize = maxDim < 512 ? 512 : (maxDim < 1024 ? 1024 : maxDim);
  final squareCanvas = img.Image(width: targetSquareSize, height: targetSquareSize, numChannels: 4);
  for (int y = 0; y < targetSquareSize; y++) {
    for (int x = 0; x < targetSquareSize; x++) {
      squareCanvas.setPixelRgba(x, y, 0, 0, 0, 0); // 100% transparent background
    }
  }

  // Scale master to fit canvas with 2% breathing room to avoid any subpixel boundary clipping
  final double scaleFactor = (targetSquareSize * 0.98) / maxDim;
  final int scaledW = (master.width * scaleFactor).round();
  final int scaledH = (master.height * scaleFactor).round();
  final scaledMaster = img.copyResize(master, width: scaledW, height: scaledH, interpolation: img.Interpolation.cubic);

  final int offsetX = ((targetSquareSize - scaledW) / 2).round();
  final int offsetY = ((targetSquareSize - scaledH) / 2).round();
  for (int y = 0; y < scaledH; y++) {
    for (int x = 0; x < scaledW; x++) {
      final p = scaledMaster.getPixel(x, y);
      squareCanvas.setPixel(x + offsetX, y + offsetY, p);
    }
  }
  final masterSquared = squareCanvas;

  // ----------------------------------------------------
  // 1. FLUTTER ASSET IMAGES (assets/images/)
  // ----------------------------------------------------
  print('--- Updating Flutter App Assets (assets/images/) ---');
  final assetsImagesDir = Directory('assets/images');
  if (!assetsImagesDir.existsSync()) {
    assetsImagesDir.createSync(recursive: true);
  }

  // assets/images/favicon.png -> Clean Circular Emblem (512x512 PNG)
  final circularFavicon512 = createCircularEmblem(master, 512);
  File('assets/images/favicon.png').writeAsBytesSync(img.encodePng(circularFavicon512));
  print('  -> assets/images/favicon.png (512x512 Round Circular PNG)');

  // assets/images/logo.png
  File('assets/images/logo.png').writeAsBytesSync(img.encodePng(circularFavicon512));
  print('  -> assets/images/logo.png (512x512 Round Circular PNG)');

  // assets/images/logo.jpg
  File('assets/images/logo.jpg').writeAsBytesSync(img.encodeJpg(circularFavicon512, quality: 95));
  print('  -> assets/images/logo.jpg (512x512 JPG)');

  // ----------------------------------------------------
  // 2. ROOT PLAY STORE ASSETS
  // ----------------------------------------------------
  print('\n--- Updating Root Store Icons ---');
  final playstore512 = img.copyResize(master, width: 512, height: 512, interpolation: img.Interpolation.cubic);
  File('playstore_icon_512.png').writeAsBytesSync(img.encodePng(playstore512));
  print('  -> playstore_icon_512.png (512x512 PNG)');

  // ----------------------------------------------------
  // 3. ANDROID LAUNCHER & STORE ICONS
  // ----------------------------------------------------
  print('\n--- Updating Android Resources (android/app/src/main/res/) ---');
  final resDir = Directory('android/app/src/main/res');

  // android/app/src/main/res/playstore-icon.png
  File('${resDir.path}/playstore-icon.png').writeAsBytesSync(img.encodePng(master));
  print('  -> android/app/src/main/res/playstore-icon.png');

  // colors.xml -> white background
  final valuesDir = Directory('${resDir.path}/values');
  if (!valuesDir.existsSync()) valuesDir.createSync(recursive: true);
  File('${valuesDir.path}/colors.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="normal_background">#FFFFFF</color>
</resources>
''');
  print('  -> android/app/src/main/res/values/colors.xml (ic_launcher_background = #FFFFFF)');

  // values-night/colors.xml -> ic_launcher_background must stay #FFFFFF to prevent black corners in Dark Mode
  final valuesNightDir = Directory('${resDir.path}/values-night');
  if (!valuesNightDir.existsSync()) valuesNightDir.createSync(recursive: true);
  File('${valuesNightDir.path}/colors.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="normal_background">#0F1520</color>
</resources>
''');
  print('  -> android/app/src/main/res/values-night/colors.xml (ic_launcher_background = #FFFFFF)');

  // Android mipmap sizes
  final legacySizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  final adaptiveSizes = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
  };

  for (final dirName in legacySizes.keys) {
    final legacySize = legacySizes[dirName]!;
    final adaptiveSize = adaptiveSizes[dirName]!;
    final targetDir = Directory('${resDir.path}/$dirName');
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

    // Legacy standard icon (solid pure white background with centered logo)
    final legacyCanvas = img.Image(width: legacySize, height: legacySize);
    for (int y = 0; y < legacySize; y++) {
      for (int x = 0; x < legacySize; x++) {
        legacyCanvas.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
    final legacyScaledLogo = img.copyResize(master, width: legacySize, height: legacySize, interpolation: img.Interpolation.cubic);
    img.compositeImage(legacyCanvas, legacyScaledLogo);
    File('${targetDir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(legacyCanvas));
    File('${targetDir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(legacyCanvas));

    // Adaptive foreground: The master logo placed squarely and safely in the central 66%-72% safe zone
    final adaptiveCanvas = img.Image(width: adaptiveSize, height: adaptiveSize);
    for (int y = 0; y < adaptiveSize; y++) {
      for (int x = 0; x < adaptiveSize; x++) {
        adaptiveCanvas.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    final int safeLogoSize = (adaptiveSize * 0.72).round();
    final scaledLogo = img.copyResize(masterSquared, width: safeLogoSize, height: safeLogoSize, interpolation: img.Interpolation.cubic);
    final int offset = ((adaptiveSize - safeLogoSize) / 2.0).round();
    for (int y = 0; y < safeLogoSize; y++) {
      for (int x = 0; x < safeLogoSize; x++) {
        final pixel = scaledLogo.getPixel(x, y);
        adaptiveCanvas.setPixel(x + offset, y + offset, pixel);
      }
    }

    File('${targetDir.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(adaptiveCanvas));
    print('  -> $dirName: ic_launcher.png, ic_launcher_round.png, ic_launcher_foreground.png');
  }

  // ----------------------------------------------------
  // 4. WEB ICONS & FAVICONS (web/)
  // ----------------------------------------------------
  print('\n--- Updating Web Assets (web/) ---');
  final webDir = Directory('web');
  if (webDir.existsSync()) {
    // web/favicon.png (192x192 Clean Circular PNG)
    final favPng = createCircularEmblem(master, 192);
    File('web/favicon.png').writeAsBytesSync(img.encodePng(favPng));
    print('  -> web/favicon.png (192x192 Round Circular PNG)');

    final webIconsDir = Directory('web/icons');
    if (!webIconsDir.existsSync()) webIconsDir.createSync(recursive: true);

    final icon192 = createCircularEmblem(master, 192);
    final icon512 = createCircularEmblem(master, 512);

    File('web/icons/Icon-192.png').writeAsBytesSync(img.encodePng(icon192));
    File('web/icons/Icon-512.png').writeAsBytesSync(img.encodePng(icon512));
    File('web/icons/Icon-maskable-192.png').writeAsBytesSync(img.encodePng(icon192));
    File('web/icons/Icon-maskable-512.png').writeAsBytesSync(img.encodePng(icon512));
    print('  -> web/icons/Icon-192.png, Icon-512.png, maskable-192, maskable-512 (Round Circular)');
  }

  // ----------------------------------------------------
  // 5. IOS APP ICONS (ios/Runner/Assets.xcassets/AppIcon.appiconset/)
  // ----------------------------------------------------
  print('\n--- Updating iOS AppIcon Assets (ios/Runner/Assets.xcassets/AppIcon.appiconset/) ---');
  final iosAppIconDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (iosAppIconDir.existsSync()) {
    final files = iosAppIconDir.listSync().whereType<File>().toList();
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.png')) {
        // Read existing image dimensions to match exact catalog dimensions
        final oldBytes = f.readAsBytesSync();
        final oldImg = img.decodeImage(oldBytes);
        final w = oldImg?.width ?? 1024;
        final h = oldImg?.height ?? 1024;
        final resized = img.copyResize(masterSquared, width: w, height: h, interpolation: img.Interpolation.cubic);
        f.writeAsBytesSync(img.encodePng(resized));
        print('  -> iOS: $name (${w}x${h} px)');
      }
    }
  }

  // iOS LaunchImage
  final iosLaunchDir = Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset');
  if (iosLaunchDir.existsSync()) {
    final files = iosLaunchDir.listSync().whereType<File>().toList();
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.png')) {
        final oldBytes = f.readAsBytesSync();
        final oldImg = img.decodeImage(oldBytes);
        final w = oldImg?.width ?? 512;
        final h = oldImg?.height ?? 512;
        final resized = img.copyResize(masterSquared, width: w, height: h, interpolation: img.Interpolation.cubic);
        f.writeAsBytesSync(img.encodePng(resized));
        print('  -> iOS LaunchImage: $name (${w}x${h} px)');
      }
    }
  }

  // ----------------------------------------------------
  // 6. MACOS APP ICONS (macos/Runner/Assets.xcassets/AppIcon.appiconset/)
  // ----------------------------------------------------
  print('\n--- Updating macOS AppIcon Assets ---');
  final macosAppIconDir = Directory('macos/Runner/Assets.xcassets/AppIcon.appiconset');
  if (macosAppIconDir.existsSync()) {
    final files = macosAppIconDir.listSync().whereType<File>().toList();
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.png')) {
        final oldBytes = f.readAsBytesSync();
        final oldImg = img.decodeImage(oldBytes);
        final w = oldImg?.width ?? 512;
        final h = oldImg?.height ?? 512;
        final resized = img.copyResize(masterSquared, width: w, height: h, interpolation: img.Interpolation.cubic);
        f.writeAsBytesSync(img.encodePng(resized));
        print('  -> macOS: $name (${w}x${h} px)');
      }
    }
  }

  // ----------------------------------------------------
  // 7. WINDOWS APP ICON (windows/runner/resources/app_icon.ico)
  // ----------------------------------------------------
  print('\n--- Updating Windows App Icon ---');
  final winIconDir = Directory('windows/runner/resources');
  if (winIconDir.existsSync()) {
    try {
      final icoFile = File('${winIconDir.path}/app_icon.ico');
      // Create ICO from 256x256 master PNG
      final icoImg = img.copyResize(masterSquared, width: 256, height: 256, interpolation: img.Interpolation.cubic);
      final icoBytes = img.encodeIco(icoImg);
      icoFile.writeAsBytesSync(icoBytes);
      print('  -> windows/runner/resources/app_icon.ico');
    } catch (e) {
      print('  [Warning] ICO encoding: $e');
    }
  }

  print('\n========================================================');
  print('  ALL PLATFORM ICONS GENERATED & SYNCED TO MASTER LOGO!');
  print('========================================================');
}
