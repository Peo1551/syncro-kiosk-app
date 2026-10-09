/// My Flexi figures from `/employee/api/flexi-summary.php`.
///
/// Every amount arrives as `{minutes, text}`. The app always shows the
/// server's text and only uses the minutes to choose a colour, so the sums
/// shown here can never drift from the portal.
class FlexiAmount {
  const FlexiAmount({required this.minutes, required this.text});

  static const FlexiAmount zero = FlexiAmount(minutes: 0, text: '0:00');

  final int minutes;
  final String text;

  bool get isZero => minutes == 0;
  bool get isNegative => minutes < 0;

  factory FlexiAmount.fromJson(Object? raw) {
    if (raw is! Map) return zero;
    final minutes = _toInt(raw['minutes']);
    final text = (raw['text'] ?? '').toString().trim();
    return FlexiAmount(minutes: minutes, text: text.isEmpty ? '0:00' : text);
  }
}

class FlexiPeriodInfo {
  const FlexiPeriodInfo({
    required this.start,
    required this.end,
    required this.daysLeft,
    required this.status,
  });

  final String start;
  final String end;
  final int daysLeft;
  final String status;

  factory FlexiPeriodInfo.fromJson(Object? raw) {
    final json = raw is Map ? raw : const {};
    return FlexiPeriodInfo(
      start: (json['start'] ?? '').toString(),
      end: (json['end'] ?? '').toString(),
      daysLeft: _toInt(json['days_left']),
      status: (json['status'] ?? '').toString().toLowerCase(),
    );
  }
}

class FlexiProjection {
  const FlexiProjection({
    required this.futureFlexiLeave,
    required this.carriedForward,
    required this.forfeited,
    required this.deduction,
  });

  final FlexiAmount futureFlexiLeave;
  final FlexiAmount carriedForward;
  final FlexiAmount forfeited;
  final FlexiAmount deduction;

  factory FlexiProjection.fromJson(Object? raw) {
    final json = raw is Map ? raw : const {};
    return FlexiProjection(
      futureFlexiLeave: FlexiAmount.fromJson(json['future_flexi_leave']),
      carriedForward: FlexiAmount.fromJson(json['carried_forward']),
      forfeited: FlexiAmount.fromJson(json['forfeited']),
      deduction: FlexiAmount.fromJson(json['deduction']),
    );
  }
}

enum FlexiNoShow { none, awaiting, balance, unpaid }

class FlexiDay {
  const FlexiDay({
    required this.date,
    required this.expected,
    required this.target,
    required this.counted,
    required this.movement,
    required this.flexiLeave,
    required this.provisional,
    required this.noShow,
  });

  final String date;
  final FlexiAmount expected;
  final FlexiAmount target;
  final FlexiAmount counted;
  final FlexiAmount movement;
  final FlexiAmount flexiLeave;
  final bool provisional;
  final FlexiNoShow noShow;

  factory FlexiDay.fromJson(Map json) {
    return FlexiDay(
      date: (json['date'] ?? '').toString(),
      expected: FlexiAmount.fromJson(json['expected']),
      target: FlexiAmount.fromJson(json['target']),
      counted: FlexiAmount.fromJson(json['counted']),
      movement: FlexiAmount.fromJson(json['movement']),
      flexiLeave: FlexiAmount.fromJson(json['flexi_leave']),
      provisional: _toBool(json['provisional']),
      noShow: _parseNoShow(json['no_show']),
    );
  }
}

class FlexiLedgerLine {
  const FlexiLedgerLine({
    required this.date,
    required this.relatedDate,
    required this.type,
    required this.amount,
    required this.reason,
  });

  final String date;
  final String? relatedDate;
  final String type;
  final FlexiAmount amount;
  final String reason;

  /// Plain-English name for the kind of entry.
  String get label {
    switch (type) {
      case 'adjustment':
        return 'Adjustment';
      case 'correction':
        return 'Correction';
      case 'no_show':
        return 'No attendance';
      case 'forfeit_paid':
        return 'Forfeited hours paid';
      default:
        final words = type.replaceAll('_', ' ').trim();
        if (words.isEmpty) return 'Adjustment';
        return words[0].toUpperCase() + words.substring(1);
    }
  }

  factory FlexiLedgerLine.fromJson(Map json) {
    final related = json['related_date'];
    return FlexiLedgerLine(
      date: (json['date'] ?? '').toString(),
      relatedDate: related == null || related.toString().trim().isEmpty
          ? null
          : related.toString(),
      type: (json['type'] ?? '').toString().toLowerCase(),
      amount: FlexiAmount.fromJson(json['amount']),
      reason: (json['reason'] ?? '').toString().trim(),
    );
  }
}

class FlexiPastPeriod {
  const FlexiPastPeriod({
    required this.start,
    required this.end,
    required this.closing,
    required this.carriedForward,
    required this.forfeited,
    required this.forfeitedPaid,
    required this.deduction,
  });

  final String start;
  final String end;
  final FlexiAmount closing;
  final FlexiAmount carriedForward;
  final FlexiAmount forfeited;
  final bool forfeitedPaid;
  final FlexiAmount deduction;

  factory FlexiPastPeriod.fromJson(Map json) {
    return FlexiPastPeriod(
      start: (json['start'] ?? '').toString(),
      end: (json['end'] ?? '').toString(),
      closing: FlexiAmount.fromJson(json['closing']),
      carriedForward: FlexiAmount.fromJson(json['carried_forward']),
      forfeited: FlexiAmount.fromJson(json['forfeited']),
      forfeitedPaid: _toBool(json['forfeited_paid']),
      deduction: FlexiAmount.fromJson(json['deduction']),
    );
  }
}

class FlexiSummary {
  const FlexiSummary({
    required this.onFlexi,
    this.scheme = '',
    this.period = const FlexiPeriodInfo(
      start: '',
      end: '',
      daysLeft: 0,
      status: '',
    ),
    this.broughtForward = FlexiAmount.zero,
    this.broughtForwardProvisional = false,
    this.earned = FlexiAmount.zero,
    this.flexiLeave = FlexiAmount.zero,
    this.adjustments = FlexiAmount.zero,
    this.balance = FlexiAmount.zero,
    this.projection = const FlexiProjection(
      futureFlexiLeave: FlexiAmount.zero,
      carriedForward: FlexiAmount.zero,
      forfeited: FlexiAmount.zero,
      deduction: FlexiAmount.zero,
    ),
    this.creditLimit = FlexiAmount.zero,
    this.debitLimit = FlexiAmount.zero,
    this.provisionalDays = 0,
    this.awaitingDecisions = 0,
    this.days = const [],
    this.ledger = const [],
    this.pastPeriods = const [],
    this.canRequestFlexiLeave = false,
  });

  static const FlexiSummary notOnFlexi = FlexiSummary(onFlexi: false);

  final bool onFlexi;
  final String scheme;
  final FlexiPeriodInfo period;
  final FlexiAmount broughtForward;
  final bool broughtForwardProvisional;
  final FlexiAmount earned;
  final FlexiAmount flexiLeave;
  final FlexiAmount adjustments;
  final FlexiAmount balance;
  final FlexiProjection projection;
  final FlexiAmount creditLimit;
  final FlexiAmount debitLimit;
  final int provisionalDays;
  final int awaitingDecisions;
  final List<FlexiDay> days;
  final List<FlexiLedgerLine> ledger;
  final List<FlexiPastPeriod> pastPeriods;
  final bool canRequestFlexiLeave;

  /// The My Flexi tile and glance figure appear only for this.
  static bool shouldShow(FlexiSummary? summary) => summary?.onFlexi == true;

  factory FlexiSummary.fromJson(Map<String, dynamic> json) {
    if (json['ok'] != true || json['on_flexi'] != true) return notOnFlexi;
    final brought = json['brought_forward'];
    final limits = json['limits'] is Map ? json['limits'] as Map : const {};
    return FlexiSummary(
      onFlexi: true,
      scheme: (json['scheme'] ?? '').toString(),
      period: FlexiPeriodInfo.fromJson(json['period']),
      broughtForward: FlexiAmount.fromJson(brought),
      broughtForwardProvisional:
          brought is Map && _toBool(brought['provisional']),
      earned: FlexiAmount.fromJson(json['earned']),
      flexiLeave: FlexiAmount.fromJson(json['flexi_leave']),
      adjustments: FlexiAmount.fromJson(json['adjustments']),
      balance: FlexiAmount.fromJson(json['balance']),
      projection: FlexiProjection.fromJson(json['projection']),
      creditLimit: FlexiAmount.fromJson(limits['credit']),
      debitLimit: FlexiAmount.fromJson(limits['debit']),
      provisionalDays: _toInt(json['provisional_days']),
      awaitingDecisions: _toInt(json['awaiting_decisions']),
      days: _mapList(json['days'], FlexiDay.fromJson),
      ledger: _mapList(json['ledger'], FlexiLedgerLine.fromJson),
      pastPeriods: _mapList(json['past_periods'], FlexiPastPeriod.fromJson),
      canRequestFlexiLeave: _toBool(json['can_request_flexi_leave']),
    );
  }
}

List<T> _mapList<T>(Object? raw, T Function(Map json) parse) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map(parse).toList(growable: false);
}

FlexiNoShow _parseNoShow(Object? raw) {
  switch ((raw ?? '').toString().trim().toLowerCase()) {
    case 'awaiting':
      return FlexiNoShow.awaiting;
    case 'balance':
      return FlexiNoShow.balance;
    case 'unpaid':
      return FlexiNoShow.unpaid;
    default:
      return FlexiNoShow.none;
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse((value ?? '').toString().trim()) ?? 0;
}

bool _toBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = (value ?? '').toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}
