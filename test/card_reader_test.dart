import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/kiosk/card_reader.dart';
import 'package:syncro_kiosk/src/kiosk/idle_countdown.dart';
import 'package:syncro_kiosk/src/kiosk/tablet.dart';

void main() {
  late DateTime now;
  late List<String> cards;
  late bool listening;
  late CardReaderBuffer reader;

  void typeChars(String text, {Duration gap = const Duration(milliseconds: 20)}) {
    for (final ch in text.split('')) {
      now = now.add(gap);
      reader.handleKey(LogicalKeyboardKey(ch.codeUnitAt(0)), ch);
    }
  }

  void enter() {
    now = now.add(const Duration(milliseconds: 20));
    reader.handleKey(LogicalKeyboardKey.enter, null);
  }

  setUp(() {
    now = DateTime(2026, 10, 9, 9);
    cards = [];
    listening = true;
    reader = CardReaderBuffer(
      onCard: cards.add,
      isListening: () => listening,
      now: () => now,
    );
  });

  test('a fast burst ending in Enter is one card', () {
    typeChars('00A1b2C3');
    enter();
    expect(cards, ['00A1b2C3']);
  });

  test('Tab also ends the card', () {
    typeChars('123456');
    reader.handleKey(LogicalKeyboardKey.tab, null);
    expect(cards, ['123456']);
  });

  test('a 500 ms pause ends a card with no Enter', () {
    fakeAsync((async) {
      reader = CardReaderBuffer(onCard: cards.add, isListening: () => listening, now: () => now);
      typeChars('98765');
      async.elapse(const Duration(milliseconds: 499));
      expect(cards, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(cards, ['98765']);
    });
  });

  test('a gap over 400 ms starts a new number', () {
    typeChars('111');
    typeChars('2222', gap: const Duration(milliseconds: 401));
    // each key after a long gap restarts the buffer
    expect(reader.pending, '2');
    typeChars('345');
    enter();
    expect(cards, ['2345']);
  });

  test('fewer than 4 characters is ignored', () {
    typeChars('123');
    enter();
    expect(cards, isEmpty);
  });

  test('other characters are not consumed', () {
    expect(reader.handleKey(LogicalKeyboardKey.minus, '-'), isFalse);
    expect(reader.pending, '');
  });

  test('nothing is collected when the screen is not listening', () {
    listening = false;
    expect(reader.handleKey(const LogicalKeyboardKey(0x31), '1'), isFalse);
    typeChars('12345');
    enter();
    expect(cards, isEmpty);
  });

  test('only key-down events count', () {
    const up = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.digit1,
      logicalKey: LogicalKeyboardKey.digit1,
      timeStamp: Duration.zero,
    );
    expect(reader.handleKeyEvent(up), isFalse);
  });

  group('idle countdown', () {
    test('counts down, resets on touch, fires once at zero', () {
      fakeAsync((async) {
        var fired = 0;
        final idle = IdleCountdown(onExpired: () => fired++);
        idle.start(60);
        async.elapse(const Duration(seconds: 59));
        expect(idle.remaining.value, 1);
        idle.reset();
        expect(idle.remaining.value, 60);
        async.elapse(const Duration(seconds: 60));
        expect(fired, 1);
        expect(idle.isRunning, isFalse);
        async.elapse(const Duration(seconds: 120));
        expect(fired, 1);
        idle.dispose();
      });
    });

    test('a zero or missing limit falls back to 60 seconds', () {
      final idle = IdleCountdown(onExpired: () {});
      idle.start(0);
      expect(idle.remaining.value, 120);
      idle.dispose();
    });

    test('tablet and session default to two minutes', () {
      expect(TabletInfo.fromJson(const {}).idleSeconds, 120);
      expect(const TabletInfo().idleSeconds, 120);
    });

    test('pill format', () {
      expect(formatCountdown(59), '0:59');
      expect(formatCountdown(5), '0:05');
      expect(formatCountdown(90), '1:30');
      expect(formatCountdown(120), '2:00');
      expect(formatCountdown(119), '1:59');
      expect(formatCountdown(180), '3:00');
      expect(formatCountdown(-3), '0:00');
    });
  });
}
