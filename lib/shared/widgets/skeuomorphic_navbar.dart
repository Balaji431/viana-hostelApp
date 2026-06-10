import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/styles.dart';

class SkeuomorphicNavBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? rightAction;
  final VoidCallback? onBack;
  final VoidCallback? onHomeTap;
  final double height;
  final VoidCallback? onTitleLongPress;

  const SkeuomorphicNavBar({
    super.key,
    required this.title,
    this.rightAction,
    this.onBack,
    this.onHomeTap,
    this.height = 56.0,
    this.onTitleLongPress,
  });

  Widget? _processRightAction(Widget? action) {
    if (action == null) return null;

    bool isRefreshButton(Widget widget) {
      if (widget is IconButton) {
        final icon = widget.icon;
        if (icon is Icon && icon.icon == Icons.refresh) {
          return true;
        }
      }
      return false;
    }

    bool isProfileButton(Widget widget) {
      return widget is ProfileButton;
    }

    bool isRedundant(Widget widget) {
      return isRefreshButton(widget) || isProfileButton(widget);
    }

    if (isRedundant(action)) {
      return null;
    }

    if (action is Row) {
      final children = action.children;
      final newChildren = <Widget>[];

      for (int i = 0; i < children.length; i++) {
        final child = children[i];
        if (isRedundant(child)) {
          continue;
        }
        newChildren.add(child);
      }

      final cleanChildren = <Widget>[];
      for (int i = 0; i < newChildren.length; i++) {
        final child = newChildren[i];
        if (child is SizedBox) {
          if (cleanChildren.isEmpty || i == newChildren.length - 1 || newChildren[i + 1] is SizedBox) {
            continue;
          }
        }
        cleanChildren.add(child);
      }

      if (cleanChildren.isEmpty) return null;
      if (cleanChildren.length == 1) return cleanChildren.first;

      return Row(
        mainAxisSize: action.mainAxisSize,
        mainAxisAlignment: action.mainAxisAlignment,
        crossAxisAlignment: action.crossAxisAlignment,
        verticalDirection: action.verticalDirection,
        textDirection: action.textDirection,
        textBaseline: action.textBaseline,
        children: cleanChildren,
      );
    }

    return action;
  }

  @override
  Widget build(BuildContext context) {
    final processedRightAction = _processRightAction(rightAction);
    return Container(
      decoration: const BoxDecoration(
        gradient: SkeuomorphicColors.royalHeaderGradient,
        border: Border(
          bottom: BorderSide(color: Color(0xFF1A2744), width: 1),
        ),
        boxShadow: [
          // Inset highlight on top (rgba(255,255,255,0.2) 0px 1px 0px 0px)
          BoxShadow(
            color: Color.fromRGBO(255, 255, 255, 0.2),
            offset: Offset(0, 1),
            blurRadius: 0,
            spreadRadius: 0,
          ),
          // Drop shadow below
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left slot: w-28
              SizedBox(
                width: 112,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: onBack != null
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                          onPressed: onBack,
                        )
                      : null,
                ),
              ),

              // Center: Title
              Expanded(
                child: GestureDetector(
                  onLongPress: onTitleLongPress,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tinos(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        const Shadow(
                          color: Color.fromRGBO(0, 0, 0, 0.3),
                          offset: Offset(0, -1),
                        ),
                        const Shadow(
                          color: Color.fromRGBO(255, 255, 255, 0.2),
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Right slot: w-28
              SizedBox(
                width: 112,
                child: processedRightAction != null
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: processedRightAction,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
}

class ProfileButton extends StatelessWidget {
  final VoidCallback? onTap;
  const ProfileButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
