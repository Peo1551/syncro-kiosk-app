import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../kiosk/tablet.dart';
import '../widgets.dart';

class WakeScreen extends StatefulWidget {
  const WakeScreen({
    super.key,
    required this.tablet,
    required this.onSignIn,
    required this.onSettings,
  });

  final TabletInfo tablet;
  final VoidCallback onSignIn;
  final VoidCallback onSettings;

  @override
  State<WakeScreen> createState() => _WakeScreenState();
}

class _WakeScreenState extends State<WakeScreen> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.tablet.placeLabel;
    return Scaffold(
      backgroundColor: kInk,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSignIn,
        child: SafeArea(
          child: Stack(
            children: [
              const Positioned(
                left: 32,
                top: 28,
                child: BrandMark(size: 44, light: true),
              ),
              Positioned(
                right: 20,
                top: 20,
                child: IconButton(
                  key: const Key('wake-settings'),
                  tooltip: 'Settings',
                  iconSize: 34,
                  padding: const EdgeInsets.all(14),
                  color: Colors.white.withValues(alpha: 0.7),
                  onPressed: widget.onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clockTime(_now),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 132,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      longDate(_now),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        place,
                        style: const TextStyle(
                          color: kGreen,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 48),
                    SizedBox(
                      height: 76,
                      child: FilledButton.icon(
                        key: const Key('wake-sign-in'),
                        onPressed: widget.onSignIn,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        icon: const Icon(Icons.contactless_outlined, size: 32),
                        label: const Text(
                          'Tap your card or touch here to sign in',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
