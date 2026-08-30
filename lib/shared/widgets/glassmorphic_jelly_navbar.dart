import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../wallpaper_provider.dart';

class GlassmorphicJellyNavbar extends StatefulWidget {
  final int currentIndex;
  final int totalTabs;
  final List<GlassmorphicTabItem> tabs;
  final ValueChanged<int> onTap;

  const GlassmorphicJellyNavbar({
    super.key,
    required this.currentIndex,
    required this.totalTabs,
    required this.tabs,
    required this.onTap,
  });

  @override
  State<GlassmorphicJellyNavbar> createState() => _GlassmorphicJellyNavbarState();
}

class _GlassmorphicJellyNavbarState extends State<GlassmorphicJellyNavbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  // Animated bounds of the jelly slider pill
  double _currentLeft = 0.0;
  double _currentRight = 0.0;
  
  // Animation keyframes
  double _startLeft = 0.0;
  double _endLeft = 0.0;
  double _startRight = 0.0;
  double _endRight = 0.0;

  bool _isDragging = false;
  double _dragX = 0.0;
  double _dragOffset = 0.0;
  int _lastHoverIndex = -1;

  // Track the layout constraints
  double _totalWidth = 0.0;
  double _tabWidth = 0.0;
  
  double get _barHeight => widget.totalTabs >= 6 ? 64.0 : 72.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _controller.addListener(_updateAnimation);
    
    // Set initial positions once width is known
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapToTab(widget.currentIndex, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant GlassmorphicJellyNavbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex && !_isDragging) {
      _snapToTab(widget.currentIndex, animate: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Dual-edge spring curves for jelly stretch effect
  void _updateAnimation() {
    final t = _controller.value;
    
    final bool movingRight = _endLeft > _startLeft;

    double leftT;
    double rightT;

    if (movingRight) {
      rightT = const ElasticOutCurve(0.85).transform(t);
      leftT = Interval(0.15, 1.0, curve: Curves.easeOutCubic).transform(t);
    } else {
      leftT = const ElasticOutCurve(0.85).transform(t);
      rightT = Interval(0.15, 1.0, curve: Curves.easeOutCubic).transform(t);
    }

    setState(() {
      _currentLeft = _startLeft + (_endLeft - _startLeft) * leftT;
      _currentRight = _startRight + (_endRight - _startRight) * rightT;
    });
  }

  void _snapToTab(int index, {required bool animate}) {
    if (_totalWidth == 0.0) return;

    final targetCenter = (index + 0.5) * _tabWidth;
    final double basePillWidth = widget.totalTabs >= 6 ? 34.0 : 44.0;
    final halfPillWidth = basePillWidth / 2;
    
    final targetLeft = targetCenter - halfPillWidth;
    final targetRight = targetCenter + halfPillWidth;

    if (animate) {
      _startLeft = _currentLeft;
      _startRight = _currentRight;
      _endLeft = targetLeft;
      _endRight = targetRight;
      _controller.forward(from: 0.0);
    } else {
      setState(() {
        _currentLeft = targetLeft;
        _currentRight = targetRight;
      });
    }
  }

  // Real-time drag updates
  void _handleDragStart(DragStartDetails details) {
    final startX = details.localPosition.dx;
    final currentCenter = _currentLeft + (_currentRight - _currentLeft) / 2;
    
    final leftLimit = widget.currentIndex * _tabWidth;
    final rightLimit = (widget.currentIndex + 1) * _tabWidth;
    
    if (startX >= leftLimit - 15 && startX <= rightLimit + 15) {
      _controller.stop();
      setState(() {
        _isDragging = true;
        _dragOffset = startX - currentCenter;
        _dragX = currentCenter;
        _lastHoverIndex = widget.currentIndex;
      });
      HapticFeedback.lightImpact();
    } else {
      _isDragging = false;
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final touchX = details.localPosition.dx;
    _dragX = (touchX - _dragOffset).clamp(0.0, _totalWidth);

    final double basePillWidth = widget.totalTabs >= 6 ? 34.0 : 44.0;
    final halfPillWidth = basePillWidth / 2;
    
    final double dragDelta = details.delta.dx;
    final double stretch = (dragDelta * 1.8).clamp(-22.0, 22.0);

    setState(() {
      if (dragDelta > 0) {
        _currentLeft = _dragX - halfPillWidth;
        _currentRight = _dragX + halfPillWidth + stretch;
      } else {
        _currentLeft = _dragX - halfPillWidth + stretch;
        _currentRight = _dragX + halfPillWidth;
      }

      final center = _currentLeft + (_currentRight - _currentLeft) / 2;
      final int activeHoverIndex = (center / _tabWidth).floor().clamp(0, widget.totalTabs - 1);
      if (activeHoverIndex != _lastHoverIndex) {
        _lastHoverIndex = activeHoverIndex;
        HapticFeedback.selectionClick();
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    final currentCenter = _currentLeft + (_currentRight - _currentLeft) / 2;
    final targetIndex = (currentCenter / _tabWidth).round().clamp(0, widget.totalTabs - 1);

    _snapToTab(targetIndex, animate: true);
    widget.onTap(targetIndex);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}

    final bool isDark = wallpaper?.isDarkTheme ?? false;
    final navBgColor = wallpaper?.navBarBackgroundColor ??
        (isDark ? const Color(0xFF101928).withOpacity(0.85) : const Color(0xFFF5F0E6).withOpacity(0.85));
    final navBorderColor = wallpaper?.navBarBorderColor ??
        const Color(0xFFD4AF37).withOpacity(0.3);
    final unselectedColor = wallpaper?.navUnselectedColor ??
        (isDark ? Colors.white60 : const Color(0xFF4A4A4A));
    final pillGradient = wallpaper?.navPillGradient ??
        (isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.22),
                  Colors.white.withOpacity(0.08),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFF5F0E6).withOpacity(0.65),
                  const Color(0xFFF5F0E6).withOpacity(0.35),
                ],
              ));

    final double horizontalMargin = widget.totalTabs >= 6 ? 8.0 : 16.0;
    final double bottomMargin = widget.totalTabs >= 6 ? 12.0 : 20.0;
    final double iconSize = widget.totalTabs >= 6 ? 20.0 : 24.0;
    final double labelFontSize = widget.totalTabs >= 6 ? 8.5 : 10.0;
    final double pillHeight = widget.totalTabs >= 6 ? 38.0 : 44.0;

    return Container(
      margin: EdgeInsets.only(left: horizontalMargin, right: horizontalMargin, bottom: bottomMargin, top: 4),
      height: _barHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            decoration: BoxDecoration(
              color: navBgColor,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: navBorderColor,
                width: 1.0,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _totalWidth = constraints.maxWidth;
                _tabWidth = _totalWidth / widget.totalTabs;

                if (_currentLeft == 0.0 && _currentRight == 0.0 && _totalWidth > 0.0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _snapToTab(widget.currentIndex, animate: false);
                  });
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glassmorphic Jelly Slider Pill
                    Positioned(
                      left: _currentLeft,
                      top: widget.totalTabs >= 6 ? 5 : 7,
                      width: (_currentRight - _currentLeft).clamp(18.0, _tabWidth * 1.5),
                      height: pillHeight,
                      child: AnimatedScale(
                        scale: _isDragging ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            gradient: pillGradient,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withOpacity(0.4),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                              BoxShadow(
                                color: const Color(0xFFD4AF37).withOpacity(_isDragging ? 0.35 : 0.2),
                                blurRadius: _isDragging ? 16 : 10,
                                spreadRadius: _isDragging ? 2 : 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Gesture Area and Icon Layer
                    GestureDetector(
                      onHorizontalDragStart: _handleDragStart,
                      onHorizontalDragUpdate: _handleDragUpdate,
                      onHorizontalDragEnd: _handleDragEnd,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: List.generate(widget.totalTabs, (index) {
                          final tab = widget.tabs[index];
                          final bool isHighlighted = (index == widget.currentIndex);

                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _snapToTab(index, animate: true);
                                widget.onTap(index);
                                HapticFeedback.lightImpact();
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: pillHeight,
                                    child: Center(
                                      child: Icon(
                                        isHighlighted ? tab.activeIcon : tab.icon,
                                        color: isHighlighted
                                            ? const Color(0xFFD4AF37)
                                            : unselectedColor,
                                        size: iconSize,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    tab.label,
                                    style: TextStyle(
                                      color: isHighlighted
                                          ? const Color(0xFFD4AF37)
                                          : unselectedColor,
                                      fontSize: labelFontSize,
                                      fontWeight: isHighlighted
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontFamily: 'Lato',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class GlassmorphicTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const GlassmorphicTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}
