import 'dart:async';

import 'package:flutter/material.dart';

/// "Request sent": the employee chooses to carry on, or is signed out when
/// the short countdown runs out.
class RequestSentPage extends StatefulWidget {
  const RequestSentPage({
    super.key,
    required this.onDoSomethingElse,
    required this.onSignOut,
    this.seconds = 8,
  });

  final VoidCallback onDoSomethingElse;
  final VoidCallback onSignOut;
  final int seconds;

  @override
  State<RequestSentPage> createState() => _RequestSentPageState();
}

class _RequestSentPageState extends State<RequestSentPage> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _timer?.cancel();
        widget.onSignOut();
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF5DA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 60,
                  color: Color(0xFF1A9C44),
                ),
              ),
              const SizedBox(height: 20),
              Text('Request sent', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Your manager will review it. You can follow it in Request History.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: OutlinedButton(
                        onPressed: () {
                          _timer?.cancel();
                          widget.onDoSomethingElse();
                        },
                        child: const Text('Do something else'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: FilledButton(
                        onPressed: () {
                          _timer?.cancel();
                          widget.onSignOut();
                        },
                        child: Text('Sign out now ($_left)'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
