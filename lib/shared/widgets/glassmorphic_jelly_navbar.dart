import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const double _barHeight = 72.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _controller.addListener(_updateAnimation);
    
    // Set initial positions once width is known (calculated in build via LayoutBuilder)
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
    
    // If moving right (endLeft > startLeft), left edge lags behind right edge
    // If moving left (endLeft < startLeft), right edge lags behind left edge
    final bool movingRight = _endLeft > _startLeft;

    double leftT;
    double rightT;

    if (movingRight) {
      // Right edge moves fast with a bouncy elastic curve
      rightT = const ElasticOutCurve(0.85).transform(t);
      // Left edge starts later (lag)
      leftT = Interval(0.15, 1.0, curve: Curves.easeOutCubic).transform(t);
    } else {
      // Left edge moves fast with bouncy elastic
      leftT = const ElasticOutCurve(0.85).transform(t);
      // Right edge lags
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
    const basePillWidth = 44.0;
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
    
    // Find the touch coordinates relative to the current active tab
    final leftLimit = widget.currentIndex * _tabWidth;
    final rightLimit = (widget.currentIndex + 1) * _tabWidth;
    
    // Allow small touch padding of 15px to make it easy to grab
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

    const basePillWidth = 44.0;
    final halfPillWidth = basePillWidth / 2;
    
    // Stretch factor based on speed/delta of the drag
    final double dragDelta = details.delta.dx;
    final double stretch = (dragDelta * 1.8).clamp(-22.0, 22.0);

    setState(() {
      if (dragDelta > 0) {
        // Dragging right: stretch right edge forward
        _currentLeft = _dragX - halfPillWidth;
        _currentRight = _dragX + halfPillWidth + stretch;
      } else {
        // Dragging left: stretch left edge backward
        _currentLeft = _dragX - halfPillWidth + stretch;
        _currentRight = _dragX + halfPillWidth;
      }

      // Live haptic ticking as slider crosses tab thresholds
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
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20, top: 8),
      height: _barHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
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
              color: const Color(0xFFF5F0E6).withOpacity(0.75), // premium light cream glass overlay
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.25),
                width: 1.0,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _totalWidth = constraints.maxWidth;
                _tabWidth = _totalWidth / widget.totalTabs;

                // Safely update position if tab centers were zero initially
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
                      top: 7,
                      width: (_currentRight - _currentLeft).clamp(20.0, _tabWidth * 1.5),
                      height: 44,
                      child: AnimatedScale(
                        scale: _isDragging ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFF5F0E6).withOpacity(0.55),
                                const Color(0xFFF5F0E6).withOpacity(0.25),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withOpacity(0.25),
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
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 7),
                                  SizedBox(
                                    height: 44,
                                    child: Center(
                                      child: Icon(
                                        isHighlighted ? tab.activeIcon : tab.icon,
                                        color: isHighlighted
                                            ? const Color(0xFFD4AF37)
                                            : const Color(0xFF4A4A4A),
                                        size: 24,
                                        shadows: null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tab.label,
                                    style: TextStyle(
                                      color: isHighlighted
                                          ? const Color(0xFFD4AF37)
                                          : const Color(0xFF4A4A4A),
                                      fontSize: 10,
                                      fontWeight: isHighlighted
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontFamily: 'Lato',
                                      shadows: null,
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
