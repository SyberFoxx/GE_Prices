import 'dart:async';

import 'package:flutter/material.dart';

class UpdatedBadge extends StatefulWidget {
  const UpdatedBadge({
    super.key,
    this.lastUpdated,
    this.style,
  });

  final DateTime? lastUpdated;
  final TextStyle? style;

  @override
  State<UpdatedBadge> createState() => _UpdatedBadgeState();
}

class _UpdatedBadgeState extends State<UpdatedBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant UpdatedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastUpdated != widget.lastUpdated) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();

    if (widget.lastUpdated == null) {
      return;
    }

    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String _label() {
    final lastUpdated = widget.lastUpdated;
    if (lastUpdated == null) {
      return 'Updated just now';
    }

    final elapsed = DateTime.now().difference(lastUpdated);
    if (elapsed.inMinutes < 1) {
      return 'Updated just now';
    }
    if (elapsed.inMinutes < 60) {
      return 'Updated ${elapsed.inMinutes}m ago';
    }
    if (elapsed.inHours < 24) {
      return 'Updated ${elapsed.inHours}h ago';
    }
    return 'Updated ${elapsed.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label(),
      style: widget.style ??
          const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
