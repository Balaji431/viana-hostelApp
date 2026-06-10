import 'package:flutter/material.dart';
import '../../core/styles.dart';

class LinenBackground extends StatelessWidget {
  final Widget child;
  const LinenBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LinenGridBackground(
      isWhite: true,
      child: child,
    );
  }
}

// CrosshatchPainter removed as we use LinenGridPainter from core/styles.dart

class SkeuomorphicButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Gradient gradient;
  final bool disabled;

  const SkeuomorphicButton({
    super.key,
    required this.child,
    this.onTap,
    this.gradient = SkeuomorphicColors.goldGlossyGradient,
    this.disabled = false,
  });

  @override
  State<SkeuomorphicButton> createState() => _SkeuomorphicButtonState();
}

class _SkeuomorphicButtonState extends State<SkeuomorphicButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.disabled ? 0.6 : 1.0,
      child: GestureDetector(
        onTapDown: widget.disabled ? null : (_) => setState(() => _isPressed = true),
        onTapUp: widget.disabled ? null : (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: widget.disabled 
              ? SkeuomorphicStyles.glossyButton(widget.gradient).copyWith(boxShadow: []) 
              : SkeuomorphicStyles.glossyButton(
                  _isPressed 
                    ? LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: widget.gradient.colors,
                      ) 
                    : widget.gradient
                ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class SkeuomorphicBadge extends StatelessWidget {
  final String text;
  final Gradient gradient;
  const SkeuomorphicBadge({super.key, required this.text, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class SkeuomorphicInput extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final bool isTextArea;
  final ValueChanged<String>? onChanged;

  const SkeuomorphicInput({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.isTextArea = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: SkeuomorphicStyles.latoBody.copyWith(fontWeight: FontWeight.bold, fontSize: 14, color: SkeuomorphicColors.residenceNavy)),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5F0E8), Colors.white],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: TextField(
            controller: controller,
            maxLines: isTextArea ? 4 : 1,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.black26),
              contentPadding: const EdgeInsets.all(16),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
