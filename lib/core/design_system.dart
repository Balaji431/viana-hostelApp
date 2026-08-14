import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RoyalTheme {
  // Colors
  static const Color primaryGoldStart = Color(0xFFE8D48A);
  static const Color primaryGoldEnd = Color(0xFFB8962E);
  static const Color goldDarkBorder = Color(0xFF8B7025);
  
  static const Color navyStart = Color(0xFF1A2744);
  static const Color navyEnd = Color(0xFF2A3A5C);
  static const Color navyDarker = Color(0xFF0F1A2E);
  
  static const Color linenStart = Color(0xFFF5F0E8);
  static const Color linenEnd = Color(0xFFE8E0D5);
  
  static const Color cardStart = Colors.white;
  static const Color cardEnd = Color(0xFFF8F5F0);
  
  static const Color subCardStart = Color(0xFFF8F5F0);
  static const Color subCardEnd = Color(0xFFF0EBE3);
  static const Color subCardBorder = Color(0xFFE0D8CC);

  // Status Colors
  static const Color successStart = Color(0xFF7DD87D);
  static const Color successMid = Color(0xFF4CAF50);
  static const Color successEnd = Color(0xFF388E3C);
  
  static const Color warningStart = Color(0xFFFFD54F);
  static const Color warningMid = Color(0xFFFFC107);
  static const Color warningEnd = Color(0xFFFFA000);
  
  static const Color dangerStart = Color(0xFFEF9A9A);
  static const Color dangerMid = Color(0xFFEF5350);
  static const Color dangerEnd = Color(0xFFE53935);
  
  static const Color infoStart = Color(0xFF81D4FA);
  static const Color infoMid = Color(0xFF29B6F6);
  static const Color infoEnd = Color(0xFF0288D1);

  static LinearGradient goldGradient = const LinearGradient(
    colors: [primaryGoldStart, primaryGoldEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static LinearGradient navyGradient = const LinearGradient(
    colors: [navyStart, navyEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class SkeuomorphicNavBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? rightAction;
  final bool showBackButton;

  const SkeuomorphicNavBar({
    super.key,
    required this.title,
    this.rightAction,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56 + MediaQuery.of(context).padding.top,
      decoration: BoxDecoration(
        gradient: RoyalTheme.navyGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(0, 2),
            blurRadius: 4,
          )
        ],
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Top highlight
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      shadows: [
                        const Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black45,
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showBackButton)
              Positioned(
                left: 8,
                top: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            if (rightAction != null)
              Positioned(
                right: 8,
                top: 4,
                child: rightAction!,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

class SkeuomorphicCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool isSubCard;

  const SkeuomorphicCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 12,
    this.isSubCard = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSubCard 
            ? [RoyalTheme.subCardStart, RoyalTheme.subCardEnd]
            : [RoyalTheme.cardStart, RoyalTheme.cardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSubCard ? RoyalTheme.subCardBorder : Colors.black.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 8,
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class SkeuomorphicButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDanger;
  final IconData? icon;

  const SkeuomorphicButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isPrimary = true,
    this.isDanger = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;
    
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: disabled
          ? LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400])
          : isDanger
            ? const LinearGradient(colors: [RoyalTheme.dangerStart, RoyalTheme.dangerEnd])
            : isPrimary 
              ? RoyalTheme.goldGradient
              : RoyalTheme.navyGradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: disabled ? Colors.grey.shade500 : Colors.black.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          if (!disabled)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              offset: const Offset(0, 2),
              blurRadius: 4,
            )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  text,
                  style: GoogleFonts.lato(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    shadows: [
                      const Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black38,
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LinenBackground extends StatelessWidget {
  final Widget child;

  const LinenBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [RoyalTheme.linenStart, RoyalTheme.linenEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // Subtle crosshatch pattern (simulated with opacity)
          Opacity(
            opacity: 0.03,
            child: GridPaper(
              color: Colors.black,
              divisions: 1,
              subdivisions: 1,
              interval: 4,
              child: Container(),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class GlossyBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color? colorOverride;

  const GlossyBadge({
    super.key,
    required this.label,
    required this.isActive,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final List<Color> gradientColors = colorOverride != null
        ? [colorOverride!.withValues(alpha: 0.7), colorOverride!]
        : (isActive
            ? [const Color(0xFF81C784), const Color(0xFF388E3C)]
            : [const Color(0xFFEF5350), const Color(0xFFD32F2F)]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
          stops: const [0.0, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, -1),
            spreadRadius: -1,
          ),
        ],
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: [
            Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 1),
          ],
        ),
      ),
    );
  }
}

class SkeuomorphicModal extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;

  const SkeuomorphicModal({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  static void show(BuildContext context, {required String title, required Widget child, List<Widget>? actions}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SkeuomorphicModal(title: title, actions: actions, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [RoyalTheme.linenStart, RoyalTheme.linenEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RoyalTheme.goldDarkBorder.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              gradient: RoyalTheme.navyGradient,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
          
          // Actions
          if (actions != null && actions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: actions!,
              ),
            ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Tactile Skeuomorphic Pill List Tile (Soft-UI embossed button with leading icon & trailing chevron)
class SkeuomorphicListTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isSelected;
  final String? subtitle;
  final Widget? trailing;
  final int? count;
  final Color? activeColor;
  final Color? iconColor;

  const SkeuomorphicListTile({
    super.key,
    required this.title,
    required this.icon,
    this.onTap,
    this.isSelected = false,
    this.subtitle,
    this.trailing,
    this.count,
    this.activeColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isSelected;
    final primaryActiveColor = activeColor ?? const Color(0xFF1976D2);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                colors: [
                  primaryActiveColor,
                  Color.alphaBlend(Colors.black.withValues(alpha: 0.15), primaryActiveColor),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF7F4EF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? primaryActiveColor.withValues(alpha: 0.8)
              : const Color(0xFFE2DACC),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: active
                ? primaryActiveColor.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.07),
            blurRadius: active ? 8 : 6,
            offset: const Offset(0, 3),
          ),
          if (!active)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.9),
              blurRadius: 2,
              offset: const Offset(0, -1),
              spreadRadius: 0,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active
                      ? Colors.white
                      : (iconColor ?? const Color(0xFF1A2744)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.lato(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : const Color(0xFF1A2744),
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: active ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (count != null && count! > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: active ? Colors.white : const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: active ? primaryActiveColor : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: active
                          ? Colors.white.withValues(alpha: 0.9)
                          : const Color(0xFF8C8477),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


