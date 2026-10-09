import 'leave_request.dart';

class LeaveEntitlement {
  const LeaveEntitlement({
    required this.yearStart,
    required this.yearEnd,
    required this.unit,
    required this.totalEntitlement,
    required this.booked,
    required this.balance,
    required this.needsSetup,
    this.isFallback = false,
  });

  final String yearStart;
  final String yearEnd;
  final String unit;
  final double totalEntitlement;
  final double booked;
  final double balance;
  final bool needsSetup;
  final bool isFallback;

  factory LeaveEntitlement.fromJson(Map<String, dynamic> json) {
    final year = (json['year'] is Map<String, dynamic>)
        ? json['year'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final entitlement = (json['entitlement'] is Map<String, dynamic>)
        ? json['entitlement'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final totals = (json['totals'] is Map<String, dynamic>)
        ? json['totals'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final totalEntitlement = (totals['total_entitlement'] is Map<String, dynamic>)
        ? totals['total_entitlement'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final taken = (totals['taken'] is Map<String, dynamic>)
        ? totals['taken'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final balance = (totals['balance'] is Map<String, dynamic>)
        ? totals['balance'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final unit = (entitlement['unit'] ?? 'DAYS').toString().trim().toUpperCase();
    final valueKey = unit == 'HOURS' ? 'hours' : 'days';

    return LeaveEntitlement(
      yearStart: (year['start'] ?? '').toString(),
      yearEnd: (year['end'] ?? '').toString(),
      unit: unit,
      totalEntitlement: _toDouble(totalEntitlement[valueKey]),
      booked: _toDouble(taken[valueKey]),
      balance: _toDouble(balance[valueKey]),
      needsSetup: _toBool(json['needs_setup']),
      isFallback: false,
    );
  }

  factory LeaveEntitlement.fallbackFromRequests({
    required Iterable<LeaveRequest> requests,
    DateTime? referenceDate,
    double defaultDays = 28,
  }) {
    final now = referenceDate ?? DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final yearEnd = DateTime(now.year, 12, 31);

    double bookedDays = 0;
    for (final request in requests) {
      if (request.groupRef.trim().toUpperCase() != 'HOL') continue;
      if (!request.keepsLeaveBooked) continue;
      bookedDays += _fallbackRequestDaysInRange(
        request,
        start: yearStart,
        end: yearEnd,
      );
    }

    final total = defaultDays;
    return LeaveEntitlement(
      yearStart: _fmtIsoDate(yearStart),
      yearEnd: _fmtIsoDate(yearEnd),
      unit: 'DAYS',
      totalEntitlement: total,
      booked: bookedDays,
      balance: total - bookedDays,
      needsSetup: true,
      isFallback: true,
    );
  }

  bool get isHours => unit == 'HOURS';

  double get progressValue {
    if (totalEntitlement <= 0) return 0;
    final ratio = booked / totalEntitlement;
    if (ratio.isNaN || ratio.isInfinite) return 0;
    return ratio.clamp(0, 1);
  }

  String formatValue(double value) {
    if (isHours) {
      return '${value.toStringAsFixed(2)} hours';
    }
    return '${value.toStringAsFixed(2)} days';
  }

  String get totalLabel => formatValue(totalEntitlement);

  String get bookedLabel => formatValue(booked);

  String get balanceLabel => formatValue(balance);
}

double _fallbackRequestDaysInRange(
  LeaveRequest request, {
  required DateTime start,
  required DateTime end,
}) {
  final from = DateTime.tryParse(request.dateFrom.trim());
  final to = DateTime.tryParse(request.dateTo.trim()) ?? from;
  if (from == null || to == null) {
    return _fallbackRequestDays(request);
  }

  final normalizedStart = DateTime(start.year, start.month, start.day);
  final normalizedEnd = DateTime(end.year, end.month, end.day);
  final requestStart = DateTime(from.year, from.month, from.day);
  final requestEnd = DateTime(to.year, to.month, to.day);
  if (requestEnd.isBefore(normalizedStart) ||
      requestStart.isAfter(normalizedEnd)) {
    return 0;
  }

  final overlapStart = requestStart.isBefore(normalizedStart)
      ? normalizedStart
      : requestStart;
  final overlapEnd = requestEnd.isAfter(normalizedEnd)
      ? normalizedEnd
      : requestEnd;
  final overlapDayCount =
      overlapEnd.difference(overlapStart).inDays.toDouble() + 1;
  final totalDayCount =
      requestEnd.difference(requestStart).inDays.toDouble() + 1;

  if (request.days > 0 && totalDayCount > 0) {
    final perDay = request.days / totalDayCount;
    return perDay * overlapDayCount;
  }

  final normalizedDayPart = request.dayPart.trim().toUpperCase();
  final multiplier = normalizedDayPart == 'AM' || normalizedDayPart == 'PM'
      ? 0.5
      : 1.0;
  return overlapDayCount * multiplier;
}

double _fallbackRequestDays(LeaveRequest request) {
  if (request.days > 0) {
    return request.days;
  }

  final from = DateTime.tryParse(request.dateFrom.trim());
  final to = DateTime.tryParse(request.dateTo.trim());
  final effectiveTo = to ?? from;
  final dayCount =
      from == null || effectiveTo == null
          ? 1.0
          : effectiveTo
                  .difference(DateTime(from.year, from.month, from.day))
                  .inDays +
              1.0;

  final normalizedDayPart = request.dayPart.trim().toUpperCase();
  final multiplier = normalizedDayPart == 'AM' || normalizedDayPart == 'PM'
      ? 0.5
      : 1.0;
  return dayCount * multiplier;
}

String _fmtIsoDate(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool _toBool(Object? raw) {
  final normalized = (raw ?? '').toString().trim().toLowerCase();
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'y';
}

double _toDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse((raw ?? '').toString().trim()) ?? 0;
}
