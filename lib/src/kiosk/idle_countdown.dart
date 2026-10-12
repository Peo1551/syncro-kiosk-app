import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Counts down whole seconds from the idle limit; any touch calls [reset].
/// [remaining] drives the "Signing out in m:ss" pill.
class IdleCountdown {
  IdleCountdown({required this.onExpired});

  final VoidCallback onExpired;
  final ValueNotifier<int> remaining = ValueNotifier<int>(0);
  int _limit = 0;
  Timer? _timer;

  bool get isRunning => _timer != null;
  int get limit => _limit;

  void start(int seconds) {
    _limit = seconds > 0 ? seconds : AppConfig.defaultIdleSeconds;
    reset();
  }

  void reset() {
    if (_limit <= 0) return;
    _timer?.cancel();
    remaining.value = _limit;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = remaining.value - 1;
      remaining.value = next < 0 ? 0 : next;
      if (next <= 0) {
        stop();
        onExpired();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    remaining.dispose();
  }
}

/// m:ss for the countdown pill.
String formatCountdown(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = (safe % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
