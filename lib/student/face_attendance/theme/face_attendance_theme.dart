import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// VianaStay Design Language System
/// Luxury skeuomorphic: deep navy + metallic gold + warm cream
class FaceAttendanceTheme {
  // ==================== PALETTE ====================
  // Gold Tokens
  static const Color goldPrimary = Color(0xFFD4AF37);
  static const Color goldDark = Color(0xFFC5A55A);
  static const Color goldDarker = Color(0xFFB8962E);
  static const Color goldLight = Color(0xFFE8D48A);
  static const Color goldBorder = Color(0xFF8B7025);
  static const Color textOnGold = Color(0xFF3D2E0A);

  // Navy Tokens
  static const Color navyDark = Color(0xFF1A2744);
  static const Color navyMedium = Color(0xFF2A3A5C);
  static const Color navyDeep = Color(0xFF0F1A2E);
  static const Color navyBlack = Color(0xFF0F1520);
  static const Color navySurface = Color(0xFF1A2235);

  // Cream & Neutral Tokens
  static const Color creamLight = Color(0xFFF5F0E8);
  static const Color creamDark = Color(0xFFE8E0D5);
  static const Color cardBgStart = Color(0xFFFFFFFF);
  static const Color cardBgEnd = Color(0xFFF8F5F0);
  static const Color tileBgStart = Color(0xFFF8F5F0);
  static const Color tileBgEnd = Color(0xFFF0EBE3);
  static const Color borderLight = Color(0xFFE0D8CC);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF888888);

  // Navy text tokens
  static const Color textOnNavyLight = Color(0xFFC8D2E0);
  static const Color textOnNavyMedium = Color(0xFFA0B0C0);
  static const Color textOnNavyDim = Color(0xFF7A8BA0);

  // Status & Feedback Tokens
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color successGreenLight = Color(0xFF66BB6A);
  static const Color successGreenMuted = Color(0xFFA5D6A7);

  static const Color dangerRed = Color(0xFFE53935);
  static const Color dangerRedLight = Color(0xFFEF5350);
  static const Color dangerRedMuted = Color(0xFFEF9A9A);
  static const Color dangerDarkText = Color(0xFF8B2020);
  static const Color dangerAlertBgStart = Color(0xFFFFEBEE);
  static const Color dangerAlertBgEnd = Color(0xFFFFCDD2);

  static const Color warningAmber = Color(0xFFFFA000);
  static const Color warningAmberLight = Color(0xFFFFD54F);
  static const Color warningDarkText = Color(0xFF5D4037);
  static const Color warningAlertBgStart = Color(0xFFFFF8E1);
  static const Color warningAlertBgEnd = Color(0xFFFFECB3);

  // ==================== GRADIENTS ====================
  // Glossy Gold Button
  static const LinearGradient glossyGoldButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFE8D48A), // 0%
      Color(0xFFD4AF37), // 45%
      Color(0xFFC5A55A), // 55%
      Color(0xFFB8962E), // 100%
    ],
    stops: [0.0, 0.45, 0.55, 1.0],
  );

  static const LinearGradient glossyGoldButtonPressed = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFB8962E),
      Color(0xFFC5A55A),
      Color(0xFFD4AF37),
      Color(0xFFE8D48A),
    ],
    stops: [0.0, 0.45, 0.55, 1.0],
  );

  // Glossy Blue Navigation Bar
  static const LinearGradient glossyNavBar = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF5B7FBF),
      Color(0xFF3D5A96),
      Color(0xFF2D4A7A),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Navy Header Band
  static const LinearGradient navyHeaderBand = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      navyDark,
      navyMedium,
    ],
  );

  // Outer Camera Frame
  static const LinearGradient outerCameraFrame = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF2A3A5C),
      Color(0xFF1A2744),
    ],
  );

  // Gold Bezel
  static const LinearGradient goldBezel = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFE8D48A),
      Color(0xFFD4AF37),
      Color(0xFFB8962E),
    ],
  );

  // Skeuomorphic Card
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      cardBgStart,
      cardBgEnd,
    ],
  );

  // Skeuomorphic Tile
  static const LinearGradient tileGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      tileBgStart,
      tileBgEnd,
    ],
  );

  // Glossy Green Button / Badge
  static const LinearGradient glossyGreenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF7DD87D),
      Color(0xFF4CAF50),
      Color(0xFF388E3C),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Grey Glossy Back Button
  static const LinearGradient glossyGreyButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF5F5F5),
      Color(0xFFE0E0E0),
      Color(0xFFCCCCCC),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // Alert Gradients
  static const LinearGradient warningAlertGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [warningAlertBgStart, warningAlertBgEnd],
  );

  static const LinearGradient dangerAlertGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [dangerAlertBgStart, dangerAlertBgEnd],
  );

  static const LinearGradient infoAlertGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cardBgStart, cardBgEnd],
  );

  // ==================== RADII ====================
  static const double radiusOuterCamera = 22.0;
  static const double radiusGoldBezel = 16.0;
  static const double radiusInnerPreview = 13.0;
  static const double radiusCard = 12.0;
  static const double radiusButton = 12.0;
  static const double radiusTile = 8.0;

  // ==================== SHADOWS ====================
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          offset: const Offset(0, 4),
          blurRadius: 12,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ];

  static List<BoxShadow> get goldButtonShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.40),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
      ];

  static List<BoxShadow> get cameraOuterShadow => [
        BoxShadow(
          color: const Color(0xFF0F1A2E).withValues(alpha: 0.32),
          offset: const Offset(0, 12),
          blurRadius: 28,
        ),
      ];

  // ==================== CENTRALIZED TYPOGRAPHY ====================
  static TextStyle get pageTitle => GoogleFonts.playfairDisplay(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: -0.2,
      );

  static TextStyle get cameraGuideText => GoogleFonts.playfairDisplay(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  static TextStyle get sectionTitle => GoogleFonts.playfairDisplay(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: navyDark,
      );

  static TextStyle get successTitle => GoogleFonts.playfairDisplay(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: navyDark,
      );

  static TextStyle get permissionTitle => GoogleFonts.playfairDisplay(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      );

  static TextStyle get bodyText => GoogleFonts.lato(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF333333),
      );

  static TextStyle get rowValue => GoogleFonts.lato(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        color: navyDark,
      );

  static TextStyle get supportingText => GoogleFonts.lato(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle get guideHintText => GoogleFonts.lato(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: textOnNavyLight,
      );

  static TextStyle get eyebrowLabel => GoogleFonts.lato(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: goldPrimary,
        letterSpacing: 1.5,
      );

  static TextStyle get tileLabel => GoogleFonts.lato(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: textMuted,
        letterSpacing: 1.2,
      );

  static TextStyle get buttonText => GoogleFonts.lato(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: textOnGold,
        letterSpacing: 1.2,
      );
}
