import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../user_provider.dart';
import '../screens/raise_issue_dialog.dart';

class RaiseIssueHeaderButton extends StatelessWidget {
  final bool compact;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? iconColor;

  const RaiseIssueHeaderButton({
    super.key,
    this.compact = false,
    this.backgroundColor,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    // Submitting issues / Help & Support is strictly reserved for Super Admin reporting to Developer
    if (user.role != UserRole.superAdmin) {
      return const SizedBox.shrink();
    }

    final double iconSize = compact ? 28.0 : 34.0;

    return Tooltip(
      message: 'Help & Report',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => RaiseIssueDialog.show(context),
          customBorder: const CircleBorder(),
          splashColor: const Color(0xFFFBBF24).withOpacity(0.2),
          highlightColor: const Color(0xFFFBBF24).withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Image.asset(
              'assets/images/help_icon.png',
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.help_outline_rounded,
                size: iconSize,
                color: const Color(0xFFFBBF24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
