import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'royal_theme.dart';

/// Royal Card - Replaces Material Card with skeuomorphic design
class RoyalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const RoyalCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: RoyalTheme.cardDecoration,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

/// Royal Primary Button - Gold gradient with skeuomorphic design
class RoyalButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final Color? textColor;
  final double? width;
  final double? height;

  const RoyalButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.textColor,
    this.width,
    this.height,
  });

  @override
  State<RoyalButton> createState() => _RoyalButtonState();
}

class _RoyalButtonState extends State<RoyalButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height ?? 48,
              decoration: BoxDecoration(
                gradient: _isPressed 
                  ? const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        RoyalTheme.goldLight,
                        RoyalTheme.goldPrimary,
                        RoyalTheme.goldMid,
                        RoyalTheme.goldDark,
                      ],
                      stops: [0.0, 0.45, 0.55, 1.0],
                    )
                  : RoyalTheme.goldGradient,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: RoyalTheme.goldBorder),
                boxShadow: RoyalTheme.buttonShadows,
              ),
              child: Center(
                child: widget.isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.textColor ?? RoyalTheme.goldText,
                          ),
                        ),
                      )
                    : Text(
                        widget.text,
                        style: RoyalTheme.buttonText.copyWith(
                          color: widget.textColor ?? RoyalTheme.goldText,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Royal Secondary Button - Blue gradient
class RoyalSecondaryButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final double? width;
  final double? height;

  const RoyalSecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.width,
    this.height,
  });

  @override
  State<RoyalSecondaryButton> createState() => _RoyalSecondaryButtonState();
}

class _RoyalSecondaryButtonState extends State<RoyalSecondaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: _handleTapCancel,
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height ?? 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF5B7FBF),
                    Color(0xFF3D5A96),
                    Color(0xFF2D4A7A),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: RoyalTheme.navyPrimary),
                boxShadow: RoyalTheme.buttonShadows,
              ),
              child: Center(
                child: Text(
                  widget.text,
                  style: RoyalTheme.buttonText.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Royal Input Field - Inset style with gradient background
class RoyalInput extends StatefulWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final Function(String)? onChanged;
  final String? Function(String?)? validator;

  const RoyalInput({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.validator,
  });

  @override
  State<RoyalInput> createState() => _RoyalInputState();
}

class _RoyalInputState extends State<RoyalInput> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: RoyalTheme.inputLabel.copyWith(
              shadows: [
                Shadow(color: Colors.white.withOpacity(0.5), offset: const Offset(0, 1)),
                Shadow(color: Colors.black.withOpacity(0.2), offset: const Offset(0, -1)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            gradient: RoyalTheme.inputGradient,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? RoyalTheme.goldPrimary : RoyalTheme.borderInput,
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: RoyalTheme.inputShadows,
          ),
          child: TextFormField(
            controller: widget.controller,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            validator: widget.validator,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: RoyalTheme.bodyMedium.copyWith(
                color: RoyalTheme.textPlaceholder,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onTap: () => setState(() => _isFocused = true),
            onTapOutside: (_) => setState(() => _isFocused = false),
          ),
        ),
      ],
    );
  }
}

/// Royal Badge - Glossy gradient pill for status indicators
class RoyalBadge extends StatelessWidget {
  final String text;
  final List<Color> gradient;
  final Color? textColor;

  const RoyalBadge({
    super.key,
    required this.text,
    required this.gradient,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.4),
            offset: const Offset(0, 1),
            blurRadius: 0,
          ), // inset highlight
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        text,
        style: RoyalTheme.badge.copyWith(color: textColor ?? Colors.white),
      ),
    );
  }
}

/// Royal Avatar - Circular gradient avatar
class RoyalAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool showBorder;

  const RoyalAvatar({
    super.key,
    required this.name,
    this.size = 64,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').map((word) => word[0]).take(2).join('').toUpperCase();
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RoyalTheme.goldGradient,
        border: showBorder 
          ? Border.all(color: RoyalTheme.goldPrimary, width: 3)
          : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.bold,
            fontSize: size * 0.3,
            color: RoyalTheme.goldText,
          ),
        ),
      ),
    );
  }
}

/// Royal Page Scaffold - Complete page with linen background
class RoyalPage extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

  const RoyalPage({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.showBackButton = false,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoyalTheme.cream,
      body: Container(
        decoration: RoyalTheme.pageDecoration,
        child: SafeArea(
          child: Column(
            children: [
              if (title != null) _buildHeader(context),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: RoyalTheme.headerDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (showBackButton)
            GestureDetector(
              onTap: onBackPressed ?? () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.24),
                      Colors.white.withOpacity(0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          if (showBackButton) const SizedBox(width: 12),
          Expanded(
            child: Text(
              title!,
              style: RoyalTheme.headingMedium.copyWith(color: Colors.white),
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// Royal Modal - Skeuomorphic dialog with blurred backdrop
class RoyalModal extends StatefulWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final double? width;
  final double? maxHeight;

  const RoyalModal({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.width,
    this.maxHeight,
  });

  @override
  State<RoyalModal> createState() => _RoyalModalState();
}

class _RoyalModalState extends State<RoyalModal> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: widget.width ?? MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: widget.maxHeight ?? MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          gradient: RoyalTheme.linenGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RoyalTheme.borderMedium),
          boxShadow: RoyalTheme.cardShadows,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: RoyalTheme.navyGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: RoyalTheme.borderMedium,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: RoyalTheme.goldGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star,
                      color: RoyalTheme.navyPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: RoyalTheme.headingMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: widget.content,
              ),
            ),
            
            // Actions
            if (widget.actions.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: RoyalTheme.borderMedium,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: widget.actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
