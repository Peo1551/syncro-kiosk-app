enum LeaveMode { dayBased, hourly, nonEntitlement, unknown }

class LeavePartDayEligibility {
  const LeavePartDayEligibility({required this.allowed, required this.reason});

  final bool allowed;
  final String reason;

  String get denialMessage {
    switch (reason) {
      case 'bank_holiday':
        return 'Part day is not available for Bank Holiday.';
      case 'daily_holiday_entitlement':
        return 'Part day holiday is only available with an hourly holiday entitlement.';
      case 'holiday_entitlement_unknown':
        return 'Hourly holiday entitlement must be loaded before choosing Part day.';
      default:
        return 'Part day is not available for this leave type.';
    }
  }
}

class LeavePartDayTimeValidation {
  const LeavePartDayTimeValidation({
    required this.valid,
    required this.message,
    this.minutes,
  });

  final bool valid;
  final String message;
  final int? minutes;
}

class LeaveSubtypeOption {
  const LeaveSubtypeOption({
    required this.subtypeId,
    required this.name,
    required this.mode,
    required this.isDefault,
    required this.isSelectable,
    required this.attachmentRequired,
  });

  final int subtypeId;
  final String name;
  final LeaveMode mode;
  final bool isDefault;
  final bool isSelectable;
  final bool attachmentRequired;

  factory LeaveSubtypeOption.fromJson(Map<String, dynamic> json) {
    return LeaveSubtypeOption(
      subtypeId: _toInt(
        json['subtype_id'] ?? json['id'] ?? json['leave_subtype_id'],
      ),
      name: (json['subtype_name'] ?? json['name'] ?? '').toString(),
      mode: _parseMode(
        (json['mode'] ?? json['request_mode'] ?? json['entitlement_mode'] ?? '')
            .toString(),
      ),
      isDefault: _toBool(json['is_default'] ?? json['default']),
      isSelectable: _toBool(
        json['is_selectable'] ?? json['allowed'] ?? json['is_allowed'] ?? 1,
      ),
      attachmentRequired: _toBool(
        json['attachment_required'] ?? json['requires_attachment'] ?? 0,
      ),
    );
  }
}

class LeaveGroupOption {
  const LeaveGroupOption({
    required this.groupId,
    required this.groupRef,
    required this.name,
    required this.mode,
    required this.attachmentRequired,
    required this.allowAlternateSubtypes,
    required this.subtypes,
    this.defaultSubtypeId,
  });

  final String groupId;
  final String groupRef;
  final String name;
  final LeaveMode mode;
  final bool attachmentRequired;
  final bool allowAlternateSubtypes;
  final int? defaultSubtypeId;
  final List<LeaveSubtypeOption> subtypes;

  LeaveSubtypeOption? get defaultSubtype {
    final id = defaultSubtypeId;
    if (id != null) {
      for (final subtype in subtypes) {
        if (subtype.subtypeId == id) return subtype;
      }
    }
    for (final subtype in subtypes) {
      if (subtype.isDefault) return subtype;
    }
    return subtypes.isEmpty ? null : subtypes.first;
  }

  factory LeaveGroupOption.fromJson(Map<String, dynamic> json) {
    final subtypesRaw = _toList(
      json['subtypes'] ?? json['allowed_subtypes'] ?? json['leave_subtypes'],
    );
    final subtypes = subtypesRaw
        .whereType<Map>()
        .map((row) => LeaveSubtypeOption.fromJson(row.cast<String, dynamic>()))
        .where((row) => row.subtypeId > 0 && row.name.trim().isNotEmpty)
        .toList();
    final groupRef = _toIdString(
      json['group_ref'] ?? json['group_id'] ?? json['type_id'] ?? json['id'],
    );
    final defaultSubtypeId = _toNullableInt(
      json['default_subtype_id'] ?? json['default_leave_subtype_id'],
    );
    final parsedMode = _parseMode(
      (json['mode'] ??
              json['request_mode'] ??
              json['entitlement_mode'] ??
              json['type_mode'] ??
              '')
          .toString(),
    );
    LeaveSubtypeOption? subtypeDefault;
    if (defaultSubtypeId != null) {
      for (final subtype in subtypes) {
        if (subtype.subtypeId == defaultSubtypeId) {
          subtypeDefault = subtype;
          break;
        }
      }
    }
    if (subtypeDefault == null) {
      for (final subtype in subtypes) {
        if (subtype.isDefault) {
          subtypeDefault = subtype;
          break;
        }
      }
    }
    subtypeDefault ??= subtypes.isEmpty ? null : subtypes.first;
    final subtypeMode = subtypeDefault?.mode ?? LeaveMode.unknown;
    final hasSubtypeAttachment = subtypes.any((row) => row.attachmentRequired);
    return LeaveGroupOption(
      groupId: groupRef,
      groupRef: groupRef,
      name: (json['group_name'] ?? json['name'] ?? '').toString(),
      mode: parsedMode == LeaveMode.unknown ? subtypeMode : parsedMode,
      attachmentRequired: _toBool(
        json['attachment_required'] ??
            json['requires_attachment'] ??
            (hasSubtypeAttachment ? 1 : 0),
      ),
      allowAlternateSubtypes: _toBool(
        json['allow_alternate_subtypes'] ??
            json['allow_subtype_choice'] ??
            json['allow_subtypes'] ??
            0,
      ),
      defaultSubtypeId: defaultSubtypeId,
      subtypes: subtypes,
    );
  }
}

LeavePartDayEligibility leavePartDayEligibility({
  required String groupRef,
  LeaveMode requestMode = LeaveMode.unknown,
  String? entitlementUnit,
}) {
  final group = groupRef.trim().toUpperCase();
  final unit = (entitlementUnit ?? '').trim().toUpperCase();

  if (group == 'BH') {
    return const LeavePartDayEligibility(
      allowed: false,
      reason: 'bank_holiday',
    );
  }
  if (group == 'HOL') {
    if (unit == 'HOURS') {
      return const LeavePartDayEligibility(
        allowed: true,
        reason: 'hourly_holiday_entitlement',
      );
    }
    return LeavePartDayEligibility(
      allowed: false,
      reason: unit == 'DAYS'
          ? 'daily_holiday_entitlement'
          : 'holiday_entitlement_unknown',
    );
  }
  if (group == 'SICK' || group == 'ABS' || group == 'TRN' || group == 'OTH') {
    return const LeavePartDayEligibility(
      allowed: true,
      reason: 'category_allows_part_day',
    );
  }
  if (requestMode == LeaveMode.hourly ||
      requestMode == LeaveMode.nonEntitlement) {
    return const LeavePartDayEligibility(
      allowed: true,
      reason: 'non_daily_entitlement_mode',
    );
  }
  return const LeavePartDayEligibility(
    allowed: false,
    reason: 'daily_entitlement_mode',
  );
}

bool leavePartDayIsSingleDate(DateTime? from, DateTime? to) {
  if (from == null || to == null) return false;
  return from.year == to.year && from.month == to.month && from.day == to.day;
}

LeavePartDayTimeValidation validateLeavePartDayTimeRange(
  int? fromMinutes,
  int? toMinutes,
) {
  if (fromMinutes == null || toMinutes == null) {
    return const LeavePartDayTimeValidation(
      valid: false,
      message: 'Start time and end time are required for Part day.',
    );
  }
  final minutes = toMinutes - fromMinutes;
  if (minutes <= 0) {
    return const LeavePartDayTimeValidation(
      valid: false,
      message: 'Start time must be before end time for Part day.',
    );
  }
  if (fromMinutes % 15 != 0 || toMinutes % 15 != 0 || minutes % 15 != 0) {
    return const LeavePartDayTimeValidation(
      valid: false,
      message: 'Part day times must use 15-minute increments.',
    );
  }
  return LeavePartDayTimeValidation(valid: true, message: '', minutes: minutes);
}

LeaveMode _parseMode(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'day_based' ||
      normalized == 'day' ||
      normalized == 'days') {
    return LeaveMode.dayBased;
  }
  if (normalized == 'hourly' || normalized == 'hours' || normalized == 'time') {
    return LeaveMode.hourly;
  }
  if (normalized == 'non_entitlement' ||
      normalized == 'non-entitlement' ||
      normalized == 'absence' ||
      normalized == 'other') {
    return LeaveMode.nonEntitlement;
  }
  return LeaveMode.unknown;
}

int _toInt(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString().trim()) ?? 0;
}

String _toIdString(Object? raw) {
  return (raw ?? '').toString().trim();
}

int? _toNullableInt(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  final parsed = int.tryParse(raw.toString().trim());
  return parsed;
}

bool _toBool(Object? raw) {
  final normalized = (raw ?? '').toString().trim().toLowerCase();
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'y';
}

List<dynamic> _toList(Object? raw) {
  if (raw is List) return raw;
  return const [];
}
