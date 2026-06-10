import 'package:flutter/material.dart';
import '../../core/styles.dart';

class SkeuoButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  final double? width;
  final bool isSecondary;
  final Color? backgroundColor;
  final Color? textColor;

  const SkeuoButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.width,
    this.isSecondary = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 50,
      decoration: BoxDecoration(
        gradient: isSecondary
            ? LinearGradient(
                colors: [Colors.white, Colors.grey.shade100],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : LinearGradient(
                colors: [
                  backgroundColor ?? AppColors.gold,
                  (backgroundColor ?? AppColors.gold).withOpacity(0.8),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: isSecondary
            ? Border.all(color: backgroundColor ?? AppColors.gold)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: isSecondary
                        ? backgroundColor ?? AppColors.gold
                        : textColor ?? Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  text,
                  style: TextStyle(
                    color: isSecondary
                        ? backgroundColor ?? AppColors.gold
                        : textColor ?? Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
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
