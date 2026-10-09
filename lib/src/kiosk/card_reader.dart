import 'dart:async';

import 'package:flutter/services.dart';

/// Collects a card number typed by a USB or Bluetooth (HID keyboard) card
/// reader. Same rules as the Visitor Connect tablet's _onCardKey: readers
/// type fast and end with Enter or Tab; a 500 ms pause also ends the number
/// for readers that send no Enter; a gap over 400 ms starts a new number;
/// fewer than 4 characters is ignored.
class CardReaderBuffer {
  CardReaderBuffer({
    required this.onCard,
    required this.isListening,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final void Function(String card) onCard;

  /// Whether the current screen accepts a card tap.
  final bool Function() isListening;
  final DateTime Function() _now;

  static const Duration keyGap = Duration(milliseconds: 400);
  static const Duration finishPause = Duration(milliseconds: 500);
  static const int minLength = 4;
  static final RegExp _cardChar = RegExp(r'^[0-9A-Za-z]$');

  final StringBuffer _buffer = StringBuffer();
  DateTime _lastKey = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  String get pending => _buffer.toString();

  /// HardwareKeyboard handler. Returns true when the key was consumed.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    return handleKey(event.logicalKey, event.character);
  }

  bool handleKey(LogicalKeyboardKey key, String? character) {
    if (!isListening()) {
      clear();
      return false;
    }
    final now = _now();
    if (now.difference(_lastKey) > keyGap) {
      _buffer.clear();
    }
    _lastKey = now;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      finish();
      return true;
    }
    final char = character ?? '';
    if (_cardChar.hasMatch(char)) {
      _buffer.write(char);
      _timer?.cancel();
      _timer = Timer(finishPause, finish);
      return true;
    }
    return false;
  }

  void finish() {
    _timer?.cancel();
    final card = _buffer.toString();
    _buffer.clear();
    if (card.length < minLength) return;
    if (!isListening()) return;
    onCard(card);
  }

  void clear() {
    _timer?.cancel();
    _buffer.clear();
  }

  void dispose() => clear();
}
