import 'package:flutter/material.dart';

/// Royal Residences Design System
/// COMPREHENSIVE THEME: Legacy Compatibility + iOS 6 Skeuomorphic Styles
class RoyalTheme {
  // ==================== LEGACY COLORS (Required for existing widgets) ====================

  static const Color goldLight = Color(0xFFF7E27D);
  static const Color goldPrimary = Color(0xFFD4AF37);
  static const Color goldMid = Color(0xFFC5A55A);
  static const Color goldDark = Color(0xFFA8872A);
  static const Color goldBorder = Color(0xFF8B7025);
  static const Color goldText = Color(0xFF3D2E0A);

  static const Color navyPrimary = Color(0xFF1A2744);
  static const Color navyDark = Color(0xFF0F1A2E);
  static const Color navyMedium = Color(0xFF2A3A5C);

  static const Color cream = Color(0xFFF5F0E8);
  static const Color creamDark = Color(0xFFE8E0D5);

  static const Color borderLight = Color(0xFFE0D8CC);
  static const Color borderMedium = Color(0xFFD0C8BC);
  static const Color borderInput = Color(0xFFB0A090);

  static const Color textPrimary = Color(0xFF1A2744);
  static const Color textBody = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textPlaceholder = Color(0xFF999999);

  // ==================== SKEUOMORPHIC TOKENS ====================

  static const Color goldTop = Color(0xFFF7E27D);
  static const Color skeuoGoldMid = Color(0xFFD4AF37);
  static const Color skeuoGoldBottom = Color(0xFFA8872A);

  static const Color skeuoInputBg = Color(0xFFEDE6DC);
  static const Color skeuoInputBorder = Color(0xFFC8BFB5);

  // ==================== TYPOGRAPHY ====================

  static TextStyle get headingLarge => const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 24,
        color: textPrimary,
      );
  static TextStyle get headingMedium => const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: textPrimary,
      );
  static TextStyle get bodyMedium => const TextStyle(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        color: textBody,
      );
  static TextStyle get badge => const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: Colors.white,
      );
  static TextStyle get inputLabel => const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: textPrimary,
      );
  static TextStyle get buttonText => const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: goldText,
      );

  // ==================== GRADIENTS ====================

  static LinearGradient get goldGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [goldLight, goldPrimary, goldMid, goldDark],
        stops: [0.0, 0.45, 0.55, 1.0],
      );

  static LinearGradient get glossyGoldGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [goldTop, skeuoGoldMid, skeuoGoldBottom],
      );

  static LinearGradient get skeuoGoldGradient => glossyGoldGradient; // Alias

  static LinearGradient get navyGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [navyPrimary, navyMedium],
      );

  static LinearGradient get leatherGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2C1810), Color(0xFF1A0F0A)],
      );

  static LinearGradient get linenGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [cream, creamDark],
      );

  static LinearGradient get inputGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [borderLight, cream, Colors.white],
        stops: [0.0, 0.08, 1.0],
      );

  static const LinearGradient glossyOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.fromRGBO(255, 255, 255, 0.5),
      Color.fromRGBO(255, 255, 255, 0.1),
      Color.fromRGBO(0, 0, 0, 0.05),
      Color.fromRGBO(0, 0, 0, 0.15),
    ],
  );

  // ==================== SHADOWS & DECORATIONS ====================

  static List<BoxShadow> get cardShadows => [
        BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 4),
            blurRadius: 12),
      ];

  static List<BoxShadow> get buttonShadows => [
        BoxShadow(
            color: Colors.black.withOpacity(0.4),
            offset: const Offset(0, 2),
            blurRadius: 6),
      ];

  static List<BoxShadow> get inputShadows => [
        BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: const Offset(0, 2),
            blurRadius: 4),
      ];

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.15)),
        boxShadow: cardShadows,
      );

  static BoxDecoration get pageDecoration => const BoxDecoration(color: cream);
  static BoxDecoration get headerDecoration =>
      BoxDecoration(gradient: navyGradient);

  // ==================== THEME DATA ====================

  static ThemeData get theme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFF0F1520),
      canvasColor: const Color(0xFF0F1520),
      primaryColor: goldPrimary,
      colorScheme: const ColorScheme.light(
        primary: goldPrimary,
        secondary: goldDark,
        surface: cream,
        onSurface: navyPrimary,
      ),
      textTheme: const TextTheme().copyWith(
        bodyMedium: bodyMedium,
        titleLarge: headingLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
            if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
            return SystemMouseCursors.click;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
            if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
            return SystemMouseCursors.click;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
            if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
            return SystemMouseCursors.click;
          }),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
            if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
            return SystemMouseCursors.click;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
            if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
            return SystemMouseCursors.click;
          }),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
      ),
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
      ),
      segmentedButtonTheme: const SegmentedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
      ),
      menuButtonTheme: const MenuButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
          if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
          return SystemMouseCursors.click;
        }),
      ),
      radioTheme: RadioThemeData(
        mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
          if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
          return SystemMouseCursors.click;
        }),
      ),
      switchTheme: SwitchThemeData(
        mouseCursor: WidgetStateProperty.resolveWith<MouseCursor>((states) {
          if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
          return SystemMouseCursors.click;
        }),
      ),
    );
  }
}

// ==================== SKEUOMORPHIC COMPONENTS ====================

class GlossyButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const GlossyButton(
      {super.key, required this.text, this.onPressed, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isLoading ? null : onPressed,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(12), // Slightly rounded like screenshot
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8C84A), // Bright gold top
              Color(0xFFCCA020), // Mid gold
              Color(0xFFAA8010), // Dark gold bottom
            ],
          ),
          border: Border.all(color: Colors.black.withOpacity(0.25), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 3)),
            BoxShadow(
                color: Colors.white.withOpacity(0.2),
                blurRadius: 0,
                offset: const Offset(0, -1)),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: RoyalTheme.glossyOverlay,
                ),
              ),
            ),
            Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: RoyalTheme.navyPrimary, strokeWidth: 3))
                  : Text(text,
                      style: const TextStyle(
                          color: Color(0xFF1A0F0A),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: 0.5)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class InsetInputField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool isPassword;
  final String? errorText;

  const InsetInputField(
      {super.key,
      required this.controller,
      required this.hint,
      this.isPassword = false,
      this.errorText});

  @override
  State<InsetInputField> createState() => _InsetInputFieldState();
}

class _InsetInputFieldState extends State<InsetInputField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
    _focusNode
        .addListener(() => setState(() => _isFocused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.errorText != null 
                  ? Colors.redAccent 
                  : (_isFocused ? const Color(0xFFCCA020) : const Color(0xFFD0C8BC)),
              width: _isFocused || widget.errorText != null ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.errorText != null
                    ? Colors.redAccent.withOpacity(0.1)
                    : (_isFocused
                        ? const Color(0xFFCCA020).withOpacity(0.15)
                        : Colors.black.withOpacity(0.06)),
                blurRadius: _isFocused ? 6 : 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: _obscureText,
            style: const TextStyle(
                color: RoyalTheme.navyPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                  fontWeight: FontWeight.w400),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscureText ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureText = !_obscureText),
                    )
                  : null,
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class SkeuomorphicCard extends StatelessWidget {
  final Widget child;
  const SkeuomorphicCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15)),
        ],
      ),
      child: child,
    );
  }
}
