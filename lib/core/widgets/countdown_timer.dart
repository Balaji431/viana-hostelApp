import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CountdownTimer extends StatefulWidget {
  final DateTime deadline;
  final VoidCallback? onExpired;
  final TextStyle? textStyle;

  const CountdownTimer({
    super.key,
    required this.deadline,
    this.onExpired,
    this.textStyle,
  });

  @override
  _CountdownTimerState createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateRemaining();
    });
  }

  void _calculateRemaining() {
    final now = DateTime.now();
    if (now.isAfter(widget.deadline)) {
      if (_remaining != Duration.zero) {
        setState(() {
          _remaining = Duration.zero;
        });
      }
      _timer?.cancel();
      if (widget.onExpired != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onExpired!();
          }
        });
      }
    } else {
      setState(() {
        _remaining = widget.deadline.difference(now);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(_remaining),
      style: widget.textStyle ??
          GoogleFonts.playfairDisplay(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFD700), // Gold
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}
