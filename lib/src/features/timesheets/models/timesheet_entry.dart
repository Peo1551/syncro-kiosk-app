class TimesheetRateLine {
  const TimesheetRateLine({
    required this.label,
    required this.minutes,
    required this.hhmm,
  });

  final String label;
  final int minutes;
  final String hhmm;

  factory TimesheetRateLine.fromJson(Map<String, dynamic> json) {
    final minutes = _toInt(json['minutes']);
    final rawLabel =
        (json['label'] ?? json['rate_name'] ?? json['name'] ?? 'Rate')
            .toString();
    return TimesheetRateLine(
      label: rawLabel.trim().isEmpty ? 'Rate' : rawLabel.trim(),
      minutes: minutes,
      hhmm: (json['hhmm'] ?? _formatMinutes(minutes)).toString(),
    );
  }
}

class TimesheetAbsenceDetail {
  const TimesheetAbsenceDetail({
    required this.requestId,
    required this.type,
    required this.description,
    required this.minutes,
    required this.hhmm,
  });

  final int requestId;
  final String type;
  final String description;
  final int minutes;
  final String hhmm;

  String get displayLabel {
    final usefulDescription = description.trim();
    return usefulDescription.isEmpty ? type.trim() : usefulDescription;
  }

  bool get hasDistinctType {
    final typeLabel = type.trim();
    return typeLabel.isNotEmpty &&
        typeLabel.toLowerCase() != displayLabel.toLowerCase();
  }

  factory TimesheetAbsenceDetail.fromJson(Map<String, dynamic> json) {
    final minutes = _toInt(json['minutes']);
    final type = (json['type'] ?? '').toString().trim();
    final description = (json['description'] ?? '').toString().trim();
    return TimesheetAbsenceDetail(
      requestId: _toInt(json['request_id']),
      type: type.isEmpty ? 'Paid leave' : type,
      description: description.isEmpty
          ? (type.isEmpty ? 'Paid leave' : type)
          : description,
      minutes: minutes,
      hhmm: (json['hhmm'] ?? _formatMinutes(minutes)).toString(),
    );
  }
}

class TimesheetEntry {
  const TimesheetEntry({
    required this.sessionId,
    required this.workDate,
    required this.clockIn,
    required this.clockOut,
    required this.totalHours,
    required this.payableMinutes,
    required this.scheduledMinutes,
    required this.status,
    required this.rates,
    this.absenceDetails = const [],
    this.requiresApproval = false,
  });

  final int sessionId;
  final String workDate;
  final String clockIn;
  final String clockOut;
  final String totalHours;
  final int payableMinutes;
  final int scheduledMinutes;
  final String status;
  final List<TimesheetRateLine> rates;
  final List<TimesheetAbsenceDetail> absenceDetails;

  /// Kiosk: timesheets.php marks a session awaiting the employee's sign-off
  /// (WorkSessions.status 'action') with requires_approval.
  final bool requiresApproval;

  factory TimesheetEntry.fromJson(Map<String, dynamic> json) {
    final ratesRaw = json['rates'];
    final rates = ratesRaw is List
        ? ratesRaw
              .whereType<Map>()
              .map(
                (row) =>
                    TimesheetRateLine.fromJson(row.cast<String, dynamic>()),
              )
              .where((row) => row.minutes > 0)
              .toList()
        : const <TimesheetRateLine>[];
    final absenceDetailsRaw = json['absence_details'];
    final absenceDetails = absenceDetailsRaw is List
        ? absenceDetailsRaw
              .whereType<Map>()
              .map(
                (row) => TimesheetAbsenceDetail.fromJson(
                  row.cast<String, dynamic>(),
                ),
              )
              .where((row) => row.minutes > 0)
              .toList()
        : const <TimesheetAbsenceDetail>[];

    return TimesheetEntry(
      sessionId: _toInt(json['session_id']),
      workDate: (json['work_date'] ?? json['date'] ?? '').toString(),
      clockIn: (json['clock_in'] ?? json['in'] ?? '--:--').toString(),
      clockOut: (json['clock_out'] ?? json['out'] ?? '--:--').toString(),
      totalHours: (json['payable_hhmm'] ?? json['total_hours'] ?? '--:--')
          .toString(),
      payableMinutes: _toInt(json['payable_minutes']),
      scheduledMinutes: _toInt(
        json['expected_paid_minutes'] ?? json['scheduled_minutes'],
      ),
      status: (json['status'] ?? '').toString(),
      rates: rates,
      absenceDetails: absenceDetails,
      requiresApproval:
          json['requires_approval'] == true ||
          json['requires_approval'] == 1 ||
          '${json['requires_approval']}' == '1' ||
          (json['status'] ?? '').toString().trim().toLowerCase() == 'action',
    );
  }

  String get dayLabel {
    final text = workDate.trim();
    if (text.length < 10) return text;
    final y = text.substring(0, 4);
    final m = text.substring(5, 7);
    final d = text.substring(8, 10);
    return '$d/$m/$y';
  }

  bool get hasRateBreakdown => rates.isNotEmpty;

  String? get absenceLabel {
    final labels = <String>[];
    final seen = <String>{};
    for (final detail in absenceDetails) {
      final label = detail.displayLabel.trim();
      if (label.isEmpty || !seen.add(label.toLowerCase())) continue;
      labels.add(label);
    }
    return labels.isEmpty ? null : labels.join(', ');
  }

  bool get shouldShowAbsenceLabelInline {
    final label = absenceLabel;
    if (label == null) return false;
    return !_normaliseText(status).contains(_normaliseText(label));
  }

  int get varianceMinutes => payableMinutes - scheduledMinutes;

  bool get hasScheduledTarget => scheduledMinutes > 0;

  bool get isOvertimeDay => hasScheduledTarget && varianceMinutes > 0;

  bool get isUnderTargetDay => hasScheduledTarget && varianceMinutes < 0;

  String? get varianceLabel {
    if (!hasScheduledTarget || varianceMinutes == 0) return null;
    final prefix = varianceMinutes > 0 ? '+' : '-';
    return '$prefix${_formatMinutes(varianceMinutes.abs())}';
  }
}

int _toInt(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString().trim()) ?? 0;
}

String _formatMinutes(int minutes) {
  final safeMinutes = minutes < 0 ? 0 : minutes;
  final hours = safeMinutes ~/ 60;
  final remainder = safeMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String _normaliseText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
