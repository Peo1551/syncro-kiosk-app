import 'package:flutter/material.dart';

import '../widgets.dart';

/// "You're signed out", shown briefly before the wake screen.
class SignedOutScreen extends StatelessWidget {
  const SignedOutScreen({super.key, this.message, required this.onDone});

  final String? message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kInk,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDone,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout_rounded, size: 88, color: kGreen),
              const SizedBox(height: 20),
              const Text(
                "You're signed out",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if ((message ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 20,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Blocking screen while the company's Syncro Kiosk add-on is off.
class UnlicensedScreen extends StatelessWidget {
  const UnlicensedScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kInk,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 56, light: true),
              const SizedBox(height: 40),
              const Text(
                'Syncro Kiosk is not active for this company',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please speak to your administrator. This tablet will carry on by itself once it is active again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 60,
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                  ),
                  child: const Text('Check again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown only if forgetting a removed pairing could not finish.
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off_rounded, size: 72, color: kAmber),
              const SizedBox(height: 16),
              Text(
                'This tablet has been removed',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              BigButton(label: 'Try again', onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
