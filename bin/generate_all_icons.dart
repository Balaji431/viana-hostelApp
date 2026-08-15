import 'dart:io';
import 'package:image/image.dart' as img;

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

  // ----------------------------------------------------
  // 1. FLUTTER ASSET IMAGES (assets/images/)
  // ----------------------------------------------------
  print('--- Updating Flutter App Assets (assets/images/) ---');
  final assetsImagesDir = Directory('assets/images');
  if (!assetsImagesDir.existsSync()) {
    assetsImagesDir.createSync(recursive: true);
  }

  // assets/images/favicon.png
  final favicon512 = img.copyResize(master, width: 512, height: 512, interpolation: img.Interpolation.cubic);
  File('assets/images/favicon.png').writeAsBytesSync(img.encodePng(favicon512));
  print('  -> assets/images/favicon.png (512x512 PNG)');

  // assets/images/logo.jpg
  File('assets/images/logo.jpg').writeAsBytesSync(img.encodeJpg(favicon512, quality: 95));
  print('  -> assets/images/logo.jpg (512x512 JPG)');

  // assets/images/logo.webp
  // Note: package:image might or might not have webp encoder in all versions; encodePng/encodeJpg or check
  try {
    // If encodeWebP is available
    final webpBytes = img.encodePng(favicon512); // fallback or check
    File('assets/images/logo.png').writeAsBytesSync(webpBytes);
  } catch (_) {}

  // ----------------------------------------------------
  // 2. ROOT PLAY STORE ASSETS
  // ----------------------------------------------------
  print('\n--- Updating Root Store Icons ---');
  File('playstore_icon_512.png').writeAsBytesSync(img.encodePng(favicon512));
  print('  -> playstore_icon_512.png (512x512 PNG)');

  // ----------------------------------------------------
  // 3. ANDROID LAUNCHER & STORE ICONS
  // ----------------------------------------------------
  print('\n--- Updating Android Resources (android/app/src/main/res/) ---');
  final resDir = Directory('android/app/src/main/res');

  // android/app/src/main/res/playstore-icon.png
  File('${resDir.path}/playstore-icon.png').writeAsBytesSync(img.encodePng(favicon512));
  print('  -> android/app/src/main/res/playstore-icon.png');

  // colors.xml -> white background
  final valuesDir = Directory('${resDir.path}/values');
  if (!valuesDir.existsSync()) valuesDir.createSync(recursive: true);
  File('${valuesDir.path}/colors.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
''');
  print('  -> android/app/src/main/res/values/colors.xml (ic_launcher_background = #FFFFFF)');

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

    // Legacy standard icon (square with exact master logo)
    final legacyImg = img.copyResize(master, width: legacySize, height: legacySize, interpolation: img.Interpolation.cubic);
    File('${targetDir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(legacyImg));
    File('${targetDir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(legacyImg));

    // Adaptive foreground: The master logo placed squarely and safely in the central 66%-72% safe zone
    final adaptiveCanvas = img.Image(width: adaptiveSize, height: adaptiveSize);
    // Fill with transparent or white background if needed; foreground is transparent with centered logo
    for (int y = 0; y < adaptiveSize; y++) {
      for (int x = 0; x < adaptiveSize; x++) {
        adaptiveCanvas.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    final int safeLogoSize = (adaptiveSize * 0.72).round();
    final scaledLogo = img.copyResize(master, width: safeLogoSize, height: safeLogoSize, interpolation: img.Interpolation.cubic);
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
    // web/favicon.png
    final favPng = img.copyResize(master, width: 64, height: 64, interpolation: img.Interpolation.cubic);
    File('web/favicon.png').writeAsBytesSync(img.encodePng(favPng));
    print('  -> web/favicon.png (64x64 PNG)');

    final webIconsDir = Directory('web/icons');
    if (!webIconsDir.existsSync()) webIconsDir.createSync(recursive: true);

    final icon192 = img.copyResize(master, width: 192, height: 192, interpolation: img.Interpolation.cubic);
    final icon512 = img.copyResize(master, width: 512, height: 512, interpolation: img.Interpolation.cubic);

    File('web/icons/Icon-192.png').writeAsBytesSync(img.encodePng(icon192));
    File('web/icons/Icon-512.png').writeAsBytesSync(img.encodePng(icon512));
    File('web/icons/Icon-maskable-192.png').writeAsBytesSync(img.encodePng(icon192));
    File('web/icons/Icon-maskable-512.png').writeAsBytesSync(img.encodePng(icon512));
    print('  -> web/icons/Icon-192.png, Icon-512.png, maskable-192, maskable-512');
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
        final resized = img.copyResize(master, width: w, height: h, interpolation: img.Interpolation.cubic);
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
        final resized = img.copyResize(master, width: w, height: h, interpolation: img.Interpolation.cubic);
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
        final resized = img.copyResize(master, width: w, height: h, interpolation: img.Interpolation.cubic);
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
      final icoImg = img.copyResize(master, width: 256, height: 256, interpolation: img.Interpolation.cubic);
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
