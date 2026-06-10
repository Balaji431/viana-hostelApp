import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  final sourcePath = r'C:\Users\daset\Desktop\favicon.png';
  final file = File(sourcePath);
  
  print('========================================================');
  print('  SIMATS STAY - Edge-Shaved Premium Gold Icon Generator');
  print('========================================================\n');
  
  if (!file.existsSync()) {
    print('[ERROR] Source image not found at: $sourcePath');
    print('Please make sure your favicon.png is placed on your Desktop.');
    return;
  }
  
  print('Loading source image...');
  final bytes = file.readAsBytesSync();
  final image = img.decodeImage(bytes);
  
  if (image == null) {
    print('[ERROR] Failed to decode image. Ensure it is a valid PNG or JPEG.');
    return;
  }
  
  print('Source image loaded successfully: ${image.width}x${image.height} px');
  
  // A beautiful, rich deep metallic gold that perfectly matches the medallion edge!
  final goldHex = '#A68037';
  print('Using premium gold background color: $goldHex');
  
  final resDir = Directory('android/app/src/main/res');
  if (!resDir.existsSync()) {
    print('[ERROR] Android resources directory not found at: ${resDir.path}');
    return;
  }
  
  // 1. WRITE COLORS.XML
  final valuesDir = Directory('${resDir.path}/values');
  if (!valuesDir.existsSync()) {
    valuesDir.createSync(recursive: true);
  }
  final colorsFile = File('${valuesDir.path}/colors.xml');
  colorsFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$goldHex</color>
</resources>
''');
  print('Created values/colors.xml with custom gold color: $goldHex');
  
  // 2. CREATE MIPMAP-ANYDPI-V26 DIRECTORY AND XML CONFIGURATIONS
  final anydpiDir = Directory('${resDir.path}/mipmap-anydpi-v26');
  if (!anydpiDir.existsSync()) {
    anydpiDir.createSync(recursive: true);
  }
  
  final adaptiveXml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''';
  
  File('${anydpiDir.path}/ic_launcher.xml').writeAsStringSync(adaptiveXml);
  File('${anydpiDir.path}/ic_launcher_round.xml').writeAsStringSync(adaptiveXml);
  print('Created mipmap-anydpi-v26 adaptive XML configs.');
  
  // 3. DEFINE SIZES FOR BOTH LEGACY AND ADAPTIVE ICONS
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
  
  print('\nGenerating launcher icons...');
  
  for (final dirName in legacySizes.keys) {
    final legacySize = legacySizes[dirName]!;
    final adaptiveSize = adaptiveSizes[dirName]!;
    
    final targetDir = Directory('${resDir.path}/$dirName');
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    
    // --- PART A: GENERATE LEGACY ICONS (SHAVED FULL-BLEED CIRCLE) ---
    final legacyResized = img.copyResize(
      image,
      width: legacySize,
      height: legacySize,
      interpolation: img.Interpolation.average,
    );
    
    // Crop to circle, shaving off 5% of the radius to completely eliminate anti-aliased white boundary lines
    final double rLegacy = legacySize / 2.0;
    final double cropLegacyRadius = rLegacy * 0.95; // Shave off 5%!
    for (int y = 0; y < legacySize; y++) {
      for (int x = 0; x < legacySize; x++) {
        final dx = x - rLegacy + 0.5;
        final dy = y - rLegacy + 0.5;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > cropLegacyRadius) {
          legacyResized.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    
    File('${targetDir.path}/ic_launcher.png').writeAsBytesSync(img.encodePng(legacyResized));
    File('${targetDir.path}/ic_launcher_round.png').writeAsBytesSync(img.encodePng(legacyResized));
    
    // --- PART B: GENERATE ADAPTIVE FOREGROUND (SHAVED CENTERED LOGO) ---
    final canvas = img.Image(width: adaptiveSize, height: adaptiveSize);
    
    // Fill canvas with full transparency
    for (int y = 0; y < adaptiveSize; y++) {
      for (int x = 0; x < adaptiveSize; x++) {
        canvas.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    
    // Resize the logo to 80% to occupy the central safe-zone beautifully
    final int logoSize = (adaptiveSize * 0.80).round();
    final logoResized = img.copyResize(
      image,
      width: logoSize,
      height: logoSize,
      interpolation: img.Interpolation.average,
    );
    
    // Apply circular crop, shaving off 5% of the radius to eliminate the white anti-aliased boundary
    final double rLogo = logoSize / 2.0;
    final double cropLogoRadius = rLogo * 0.95; // Shave off 5%!
    for (int y = 0; y < logoSize; y++) {
      for (int x = 0; x < logoSize; x++) {
        final dx = x - rLogo + 0.5;
        final dy = y - rLogo + 0.5;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > cropLogoRadius) {
          logoResized.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    
    // Draw the cropped logo directly in the center of the transparent canvas
    final int offset = ((adaptiveSize - logoSize) / 2.0).round();
    for (int y = 0; y < logoSize; y++) {
      for (int x = 0; x < logoSize; x++) {
        final pixel = logoResized.getPixel(x, y);
        canvas.setPixel(x + offset, y + offset, pixel);
      }
    }
    
    File('${targetDir.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(canvas));
    
    print('  -> $dirName: Generated legacy and adaptive layers (shaved).');
  }
  
  print('\n========================================================');
  print('[SUCCESS] Edge-shaved launcher icons generated successfully!');
  print('========================================================');
}
