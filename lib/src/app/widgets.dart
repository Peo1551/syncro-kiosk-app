import 'package:flutter/material.dart';

const kInk = Color(0xFF102F08);
const kGreen = Color(0xFF8DC63E);
const kBg = Color(0xFFF5F7FB);
const kMuted = Color(0xFF667085);
const kDanger = Color(0xFFDC2626);
const kAmber = Color(0xFFF59E0B);
const kLine = Color(0xFFE6E8EE);

/// Big-key numeric keypad (keys are at least 64 px tall).
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    this.enabled = true,
    this.keyHeight = 68,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool enabled;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback onTap, {Widget? child, Key? k}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: keyHeight,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                key: k,
                borderRadius: BorderRadius.circular(18),
                onTap: enabled ? onTap : null,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kLine),
                  ),
                  child: Center(
                    child:
                        child ??
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: enabled ? kInk : kMuted,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget digit(String d) => key(d, () => onDigit(d), k: Key('key-$d'));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: row.map(digit).toList()),
        Row(
          children: [
            key(
              'Clear',
              onClear,
              k: const Key('key-clear'),
              child: const Text(
                'Clear',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            digit('0'),
            key(
              '',
              onBackspace,
              k: const Key('key-back'),
              child: const Icon(Icons.backspace_outlined, size: 28),
            ),
          ],
        ),
      ],
    );
  }
}

/// The entered value: digits, or dots for a PIN.
class EntryDisplay extends StatelessWidget {
  const EntryDisplay({
    super.key,
    required this.value,
    this.obscure = false,
    this.placeholder = '',
  });

  final String value;
  final bool obscure;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final text = value.isEmpty
        ? placeholder
        : obscure
        ? '•' * value.length
        : value;
    return Container(
      height: 72,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLine, width: 2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 34,
          letterSpacing: obscure ? 8 : 4,
          fontWeight: FontWeight.w800,
          color: value.isEmpty ? kMuted.withValues(alpha: 0.5) : kInk,
        ),
      ),
    );
  }
}

/// Six boxes for the pairing code.
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({super.key, required this.code, this.length = 6});

  final String code;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final filled = i < code.length;
        return Container(
          width: 58,
          height: 70,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: i == code.length ? kGreen : kLine,
              width: 2,
            ),
          ),
          child: Text(
            filled ? code[i] : '',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: kInk,
            ),
          ),
        );
      }),
    );
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: kDanger, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.asset(
            'assets/app-icon.png',
            width: size,
            height: size,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              color: kGreen,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Syncro Kiosk',
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w900,
            color: light ? Colors.white : kInk,
          ),
        ),
      ],
    );
  }
}

/// Primary kiosk action button: tall, full width.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        child: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : Text(label),
      ),
    );
  }
}
