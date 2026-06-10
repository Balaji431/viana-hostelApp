import 'package:flutter/material.dart';
import '../../core/styles.dart';

class InsetContent extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;

  const InsetContent({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 15,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
          BoxShadow(
            color: Colors.white,
            blurRadius: 4,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class EmbossedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;

  const EmbossedCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class GlossyGoldButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const GlossyGoldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: SkeuomorphicColors.goldGlossyGradient,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black12),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: SkeuomorphicColors.residenceBrown, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF291E1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
        ),
      ),
    );
  }
}

class InsetInputField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final bool obscure;
  final IconData? icon;

  const InsetInputField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.obscure = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: SkeuomorphicColors.residenceNavy,
              fontSize: 14,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade400),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 4,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}


