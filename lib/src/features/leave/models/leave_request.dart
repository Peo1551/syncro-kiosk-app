class LeaveRequest {
  const LeaveRequest({
    required this.requestId,
    required this.employeeId,
    required this.dateFrom,
    required this.dateTo,
    required this.groupRef,
    required this.groupName,
    required this.subtypeName,
    required this.dayPart,
    required this.status,
    required this.statusLabel,
    required this.notes,
    this.timeFrom,
    this.timeTo,
    this.days = 0,
    this.minutes = 0,
    this.source,
    this.createdByEmployeeId,
    this.isRequested = true,
    this.hasAttachment = false,
    this.canCancel = false,
    this.canRequestRemoval = false,
    this.removalStatus,
    this.removalStatusLabel,
  });

  final int requestId;
  final int employeeId;
  final String dateFrom;
  final String dateTo;
  final String groupRef;
  final String groupName;
  final String subtypeName;
  final String dayPart;
  final String? timeFrom;
  final String? timeTo;
  final String status;
  final String statusLabel;
  final String notes;
  final double days;
  final int minutes;
  final String? source;
  final int? createdByEmployeeId;
  final bool isRequested;
  final bool hasAttachment;
  final bool canCancel;
  final bool canRequestRemoval;
  final String? removalStatus;
  final String? removalStatusLabel;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] ?? '').toString().trim();
    final normalizedStatus = status.toLowerCase();
    final source = _toNullableString(json['source']);
    final normalizedSource = source?.trim().toUpperCase();
    final createdByEmployeeId = _toInt(json['created_by_emp']);
    final employeeId = _toInt(json['employee_id']);
    final removalStatus = _toNullableString(json['removal_status']);
    final createdAt = _toNullableString(json['created_at']);
    final updatedAt = _toNullableString(json['updated_at']);
    final hasExplicitIsRequested = json.containsKey('is_requested');
    final changedAfterCreate =
        createdAt != null &&
        updatedAt != null &&
        DateTime.tryParse(updatedAt)?.isAfter(DateTime.tryParse(createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0)) ==
            true;
    final inferredRequested =
        normalizedStatus == 'pending' ||
        (normalizedSource != null &&
            {'APP', 'MOBILE', 'EMPLOYEE'}.contains(normalizedSource)) ||
        (removalStatus ?? '').trim().isNotEmpty ||
        changedAfterCreate;
    final canCancel =
        _toBool(json['can_cancel']) || normalizedStatus == 'pending';
    final canRequestRemoval =
        _toBool(json['can_request_removal']) || normalizedStatus == 'approved';
    final attachmentCount = _toInt(json['attachment_count']);
    final hasAttachment =
        _toBool(json['has_attachment']) || attachmentCount > 0;
    return LeaveRequest(
      requestId: _toInt(json['request_id'] ?? json['id']),
      employeeId: employeeId,
      dateFrom: (json['date_from'] ?? json['start_date'] ?? '').toString(),
      dateTo: (json['date_to'] ?? json['end_date'] ?? '').toString(),
      groupRef: (json['group_ref'] ?? json['group_id'] ?? '').toString(),
      groupName:
          (json['group_name'] ?? json['type_name'] ?? json['group'] ?? '')
              .toString(),
      subtypeName: (json['subtype_name'] ?? json['subtype'] ?? '').toString(),
      dayPart: (json['day_part'] ?? 'FULL').toString(),
      timeFrom: _toNullableString(json['time_from']),
      timeTo: _toNullableString(json['time_to']),
      status: status.isEmpty ? 'Pending' : status,
      statusLabel:
          (json['status_label'] ?? json['status'] ?? 'Pending').toString(),
      notes: (json['notes'] ?? json['reason'] ?? '').toString(),
      days: _toDouble(json['days']),
      minutes: _toInt(json['minutes']),
      source: source,
      createdByEmployeeId: createdByEmployeeId > 0 ? createdByEmployeeId : null,
      isRequested: hasExplicitIsRequested
          ? _toBool(json['is_requested'])
          : inferredRequested,
      hasAttachment: hasAttachment,
      canCancel: canCancel,
      canRequestRemoval: canRequestRemoval,
      removalStatus: removalStatus,
      removalStatusLabel: _toNullableString(json['removal_status_label']),
    );
  }

  String get normalizedStatus => status.trim().toLowerCase();

  String get normalizedRemovalStatus =>
      (removalStatus ?? '').trim().toLowerCase();

  bool get hasRemovalApproved =>
      normalizedRemovalStatus.contains('approved') ||
      normalizedRemovalStatus.contains('complete');

  bool get hasRemovalRejected =>
      normalizedRemovalStatus.contains('rejected') ||
      normalizedRemovalStatus.contains('declined');

  bool get hasPendingRemoval => _isPendingLike(normalizedRemovalStatus);

  bool get hasPendingRemovalWorkflow =>
      hasPendingRemoval ||
      (_isPendingLike(normalizedStatus) &&
          (normalizedStatus.contains('cancel') ||
              normalizedStatus.contains('remov')));

  bool get hasRemovalDecision => hasRemovalApproved || hasRemovalRejected;

  bool get isPendingWorkflow =>
      _isPendingLike(normalizedStatus) || hasPendingRemovalWorkflow;

  bool get keepsLeaveBooked {
    if (hasRemovalApproved) return false;
    return normalizedStatus.contains('approved') ||
        normalizedStatus.contains('complete') ||
        hasPendingRemovalWorkflow;
  }

  bool get isHistoryApproved {
    if (hasRemovalDecision) {
      return hasRemovalApproved;
    }
    if (hasPendingRemovalWorkflow) {
      return false;
    }
    return normalizedStatus.contains('approved') ||
        normalizedStatus.contains('complete');
  }

  bool get isHistoryRejected {
    if (hasRemovalDecision) {
      return hasRemovalRejected;
    }
    return normalizedStatus.contains('rejected') ||
        normalizedStatus.contains('declined') ||
        normalizedStatus.contains('cancelled');
  }

  String get activeStatusLabel {
    if (hasRemovalApproved) {
      return removalStatusLabel ?? 'Removal approved';
    }
    if (hasRemovalRejected) {
      return removalStatusLabel ?? 'Removal rejected';
    }
    if (hasPendingRemovalWorkflow) {
      final label = removalStatusLabel?.trim();
      if (label != null && label.isNotEmpty) {
        return removalStatusLabel!;
      }
      final status = statusLabel.trim();
      return status.isEmpty ? 'Removal pending' : statusLabel;
    }
    final label = statusLabel.trim();
    return label.isEmpty ? 'Pending' : statusLabel;
  }

  String get historyStatusLabel {
    if (hasRemovalApproved) {
      return removalStatusLabel ?? 'Removal approved';
    }
    if (hasRemovalRejected) {
      return removalStatusLabel ?? 'Removal rejected';
    }
    if (normalizedStatus.contains('cancelled')) {
      return 'Rejected request';
    }
    return statusLabel;
  }

  String? get removalStatusText {
    if (removalStatusLabel != null && removalStatusLabel!.trim().isNotEmpty) {
      return removalStatusLabel;
    }
    final text = (removalStatus ?? '').trim();
    if (text.isEmpty) return null;
    return text;
  }

  String get dateRangeText {
    if (dateFrom.isEmpty && dateTo.isEmpty) return '--';
    if (dateTo.isEmpty || dateFrom == dateTo) return _fmtDate(dateFrom);
    return '${_fmtDate(dateFrom)} - ${_fmtDate(dateTo)}';
  }

  String get dayPartLabel {
    final value = dayPart.trim().toLowerCase();
    if (value == 'first_half' || value == 'am') return 'First half';
    if (value == 'second_half' || value == 'pm') return 'Second half';
    return 'Full day';
  }

  String? get timeRangeText {
    final from = (timeFrom ?? '').trim();
    final to = (timeTo ?? '').trim();
    if (from.isEmpty && to.isEmpty) return null;
    if (to.isEmpty) return from;
    if (from.isEmpty) return to;
    return '$from - $to';
  }

  String _fmtDate(String raw) {
    final text = raw.trim();
    if (text.length < 10) return text;
    final y = text.substring(0, 4);
    final m = text.substring(5, 7);
    final d = text.substring(8, 10);
    return '$d/$m/$y';
  }
}

bool _toBool(Object? raw) {
  final normalized = (raw ?? '').toString().trim().toLowerCase();
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'y';
}

int _toInt(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString().trim()) ?? 0;
}

double _toDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse((raw ?? '').toString().trim()) ?? 0;
}

String? _toNullableString(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return null;
  return text;
}

bool _isPendingLike(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('pending') ||
      normalized.contains('await') ||
      normalized.contains('submitted') ||
      normalized.contains('processing') ||
      normalized.contains('requested');
}
