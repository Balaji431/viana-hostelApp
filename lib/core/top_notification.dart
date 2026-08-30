import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

enum TopNotificationType { error, warning, success, info }

class TopNotification {
  static OverlayEntry? _currentEntry;

  /// Dismisses any currently visible top notification
  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }

  /// Displays a floating top-of-screen notification banner
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    TopNotificationType type = TopNotificationType.info,
    Duration duration = const Duration(seconds: 5),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    // Dismiss existing notification
    dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopNotificationWidget(
        title: title,
        message: message,
        type: type,
        duration: duration,
        onAction: onAction,
        actionLabel: actionLabel,
        onDismiss: () {
          if (_currentEntry == entry) {
            dismiss();
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  /// Convenience method for Insufficient Wallet Balance errors
  static void showInsufficientBalance(
    BuildContext context, {
    required double currentBalance,
    required double requiredAmount,
    VoidCallback? onTopUp,
  }) {
    final shortage = requiredAmount - currentBalance;
    final formatter = NumberFormat('#,##,###.##');
    final formattedShortage = formatter.format(shortage > 0 ? shortage : 0);
    final formattedBalance = formatter.format(currentBalance);
    final formattedRequired = formatter.format(requiredAmount);

    show(
      context,
      type: TopNotificationType.error,
      duration: const Duration(seconds: 6),
      title: 'Insufficient Wallet Balance',
      message: 'Need ₹$formattedShortage more (Have ₹$formattedBalance / Need ₹$formattedRequired).',
      actionLabel: 'Add Funds',
      onAction: onTopUp,
    );
  }

  /// Convenience method for Success messages
  static void showSuccess(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    show(
      context,
      type: TopNotificationType.success,
      duration: const Duration(seconds: 4),
      title: title,
      message: message,
    );
  }

  /// Convenience method for generic Error messages
  static void showError(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    show(
      context,
      type: TopNotificationType.error,
      duration: const Duration(seconds: 5),
      title: title,
      message: message,
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String title;
  final String message;
  final TopNotificationType type;
  final Duration duration;
  final VoidCallback? onAction;
  final String? actionLabel;
  final VoidCallback onDismiss;

  const _TopNotificationWidget({
    required this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    this.onAction,
    this.actionLabel,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();

    // Auto dismiss
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _primaryColor {
    switch (widget.type) {
      case TopNotificationType.error:
        return const Color(0xFFEF4444);
      case TopNotificationType.warning:
        return const Color(0xFFF59E0B);
      case TopNotificationType.success:
        return const Color(0xFF10B981);
      case TopNotificationType.info:
        return const Color(0xFF3B82F6);
    }
  }

  Color get _backgroundColor {
    switch (widget.type) {
      case TopNotificationType.error:
        return const Color(0xFFFEF2F2);
      case TopNotificationType.warning:
        return const Color(0xFFFFFBEB);
      case TopNotificationType.success:
        return const Color(0xFFECFDF5);
      case TopNotificationType.info:
        return const Color(0xFFEFF6FF);
    }
  }

  Color get _borderColor {
    switch (widget.type) {
      case TopNotificationType.error:
        return const Color(0xFFFCA5A5);
      case TopNotificationType.warning:
        return const Color(0xFFFCD34D);
      case TopNotificationType.success:
        return const Color(0xFF6EE7B7);
      case TopNotificationType.info:
        return const Color(0xFF93C5FD);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case TopNotificationType.error:
        return Icons.error_rounded;
      case TopNotificationType.warning:
        return Icons.warning_amber_rounded;
      case TopNotificationType.success:
        return Icons.check_circle_rounded;
      case TopNotificationType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                  _dismiss();
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: _primaryColor.withOpacity(0.08),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Icon badge
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_icon, color: _primaryColor, size: 22),
                      ),
                      const SizedBox(width: 12),

                      // Text info
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.message,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF475569),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Optional Action Button
                      if (widget.onAction != null && widget.actionLabel != null) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            _dismiss();
                            widget.onAction!();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],

                      // Close button
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _dismiss,
                        icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
