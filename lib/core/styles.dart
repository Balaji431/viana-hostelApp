import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color gold = Color(0xFFD4AF37);
  static const Color navy = Color(0xFF1B2B48);
  static const Color navyDark = Color(0xFF0F1A2E);
  static const Color background = Color(0xFFF5F0E8);
}

class SkeuomorphicColors {
  // Warmer Base Palette
  static const Color luxuryGreen = Color(0xFF1B4D3E);
  static const Color luxuryGold = Color(0xFFD4AF37);
  static const Color warmBronze = Color(0xFF8C6239);
  static const Color warmCream = Color(0xFFF5F0E8);
  static const Color deepEspresso = Color(0xFF2A1E1A);
  
  static const Color ios6Blue = Color(0xFF3875D7); // Kept for functional UI components
  static const Color ios6Silver = Color(0xFFD0D0D0);
  static const Color contentBg = Color(0xFFF0EAE2);
  static const Color pinstripe = Color(0xFFD3CFC4);
  
  // Specific Warden/Student Colors
  static const Color residenceBrown = Color(0xFF291E1A);
  static const Color residenceGold = Color(0xFFC5A358);
  static const Color residenceNavy = Color(0xFF1B2B48);
  static const Color residenceMutedText = Color(0xFFA0B0C0);
  static const Color residenceCardBg = Color(0xFFFFFFFF);
  static const Color residenceMainBg = Color(0xFFF5F0E8);
  static const Color residenceMainBgEnd = Color(0xFFE8E0D5);
  
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color warningGold = Color(0xFFE0B400);
  static const Color absentRed = Color(0xFFB71C1C);

  // Gradients
  static const Gradient goldGlossyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFE8D48A),
      Color(0xFFD4AF37),
      Color(0xFFB8962E),
    ],
    stops: [0.0, 0.5, 1.0],
  );
  
  static const Gradient softBrownGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFA1887F),
      Color(0xFF8D6E63),
      Color(0xFF6D4C41),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const Gradient warmHeaderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF2A1E1A),
      Color(0xFF3D2B25),
    ],
  );

  static const Gradient navyAppBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF5B7FBF),
      Color(0xFF3D5A96),
      Color(0xFF2D4A7A),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const Gradient royalHeaderGradient = navyAppBarGradient;

  static const Gradient royalBlueGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF5B7FBF),
      Color(0xFF3D5A96),
      Color(0xFF2D4A7A),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const Gradient royalContentGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1A2744),
      Color(0xFF2A3A5C),
    ],
  );

  static const Gradient successGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF7DD87D),
      Color(0xFF4CAF50),
      Color(0xFF388E3C),
    ],
  );

  static const Gradient dangerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFEF9A9A),
      Color(0xFFEF5350),
      Color(0xFFE53935),
    ],
  );

  static const Gradient warningGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFD54F),
      Color(0xFFFFC107),
      Color(0xFFFFA000),
    ],
  );

  static const Gradient infoGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF81D4FA),
      Color(0xFF29B6F6),
      Color(0xFF0288D1),
    ],
  );

  static const Gradient mainBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF5F0E8),
      Color(0xFFE8E0D5),
    ],
  );

  static BoxDecoration get linenGridDecoration => BoxDecoration(
    color: warmCream,
    gradient: mainBackgroundGradient,
  );
}

class LinenGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.03)
      ..strokeWidth = 2;

    // Horizontal lines every 4px
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y + 2), Offset(size.width, y + 2), paint);
    }

    // Vertical lines every 4px
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawLine(Offset(x + 2, 0), Offset(x + 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LinenGridBackground extends StatelessWidget {
  final Widget child;
  final bool isWhite;
  const LinenGridBackground({super.key, required this.child, this.isWhite = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: isWhite ? Colors.white : const Color(0xFFF5F0E8),
              gradient: isWhite ? null : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF5F0E8), Color(0xFFE8E0D5)],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: LinenGridPainter(),
          ),
        ),
        child,
      ],
    );
  }
}

class SkeuomorphicStyles {
  static TextStyle playfairHeader = GoogleFonts.tinos(
    fontWeight: FontWeight.bold,
  );

  static TextStyle latoBody = GoogleFonts.tinos();

  static BoxDecoration skeuomorphicCard = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.black.withOpacity(0.1), width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // Restored glossyButton method
  static BoxDecoration glossyButton(Gradient gradient) => BoxDecoration(
    gradient: gradient,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.black26),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 4,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
