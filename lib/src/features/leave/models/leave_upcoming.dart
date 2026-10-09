class LeaveUpcomingViews {
  const LeaveUpcomingViews({
    required this.canViewTeam,
    required this.canViewCompany,
    required this.team,
    required this.company,
  });

  final bool canViewTeam;
  final bool canViewCompany;
  final List<LeaveUpcomingEntry> team;
  final List<LeaveUpcomingEntry> company;

  factory LeaveUpcomingViews.fromJson(Map<String, dynamic> json) {
    final permissions = _firstMap([
      json['permissions'],
      json['data'] is Map ? (json['data'] as Map)['permissions'] : null,
      json['payload'] is Map ? (json['payload'] as Map)['permissions'] : null,
    ]);
    return LeaveUpcomingViews(
      canViewTeam: _toBool(
        json['team_allowed'] ??
            json['can_view_team'] ??
            permissions['view_team_leave'],
      ),
      canViewCompany: _toBool(
        json['company_allowed'] ??
            json['can_view_company'] ??
            permissions['view_company_leave'],
      ),
      team: _firstList([
            json['team'],
            json['my_team'],
            json['team_rows'],
            json['views'] is Map ? (json['views'] as Map)['team'] : null,
            json['views'] is Map ? (json['views'] as Map)['my_team'] : null,
            json['data'] is Map ? (json['data'] as Map)['team'] : null,
            json['data'] is Map ? (json['data'] as Map)['my_team'] : null,
            json['payload'] is Map ? (json['payload'] as Map)['team'] : null,
            json['payload'] is Map ? (json['payload'] as Map)['my_team'] : null,
          ])
          .whereType<Map>()
          .map((row) => LeaveUpcomingEntry.fromJson(row.cast<String, dynamic>()))
          .toList(),
      company: _firstList([
            json['company'],
            json['whole_company'],
            json['company_rows'],
            json['views'] is Map ? (json['views'] as Map)['company'] : null,
            json['views'] is Map ? (json['views'] as Map)['whole_company'] : null,
            json['data'] is Map ? (json['data'] as Map)['company'] : null,
            json['data'] is Map ? (json['data'] as Map)['whole_company'] : null,
            json['payload'] is Map ? (json['payload'] as Map)['company'] : null,
            json['payload'] is Map ? (json['payload'] as Map)['whole_company'] : null,
          ])
          .whereType<Map>()
          .map((row) => LeaveUpcomingEntry.fromJson(row.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class LeaveUpcomingEntry {
  const LeaveUpcomingEntry({
    required this.dateFrom,
    required this.dateTo,
    required this.groupRef,
    required this.groupName,
    required this.subtypeName,
    required this.dayPart,
    required this.people,
    required this.count,
  });

  final String dateFrom;
  final String dateTo;
  final String groupRef;
  final String groupName;
  final String subtypeName;
  final String dayPart;
  final List<LeaveUpcomingPerson> people;
  final int count;

  factory LeaveUpcomingEntry.fromJson(Map<String, dynamic> json) {
    final people = _toList(json['people'])
        .whereType<Map>()
        .map((row) => LeaveUpcomingPerson.fromJson(row.cast<String, dynamic>()))
        .where((row) => row.employeeId > 0 || row.name.trim().isNotEmpty)
        .toList();
    return LeaveUpcomingEntry(
      dateFrom: _toText(json['date_from'] ?? json['start_date']),
      dateTo: _toText(json['date_to'] ?? json['end_date']),
      groupRef: _toText(json['group_ref']),
      groupName: _toText(json['group_name']),
      subtypeName: _toText(json['subtype_name']),
      dayPart: _toText(json['day_part']),
      people: people,
      count: _toInt(json['count']) > 0 ? _toInt(json['count']) : people.length,
    );
  }

  String get dateRangeText {
    if (dateFrom.isEmpty && dateTo.isEmpty) return '--';
    if (dateTo.isEmpty || dateFrom == dateTo) return _fmtDate(dateFrom);
    return '${_fmtDate(dateFrom)} - ${_fmtDate(dateTo)}';
  }

  String get dayPartLabel {
    final value = dayPart.trim().toLowerCase();
    if (value == 'am' || value == 'first_half') return 'First half';
    if (value == 'pm' || value == 'second_half') return 'Second half';
    return 'Full day';
  }

  String get typeLabel {
    final subtype = subtypeName.trim();
    if (subtype.isNotEmpty) return subtype;
    final group = groupName.trim();
    if (group.isNotEmpty) return group;
    return groupRef.trim().isEmpty ? 'Leave' : groupRef.trim();
  }

  String _fmtDate(String raw) {
    final text = raw.trim();
    if (text.length < 10) return text;
    return '${text.substring(8, 10)}/${text.substring(5, 7)}/${text.substring(0, 4)}';
  }
}

class LeaveUpcomingPerson {
  const LeaveUpcomingPerson({
    required this.employeeId,
    required this.name,
    required this.departmentName,
    required this.siteName,
  });

  final int employeeId;
  final String name;
  final String departmentName;
  final String siteName;

  factory LeaveUpcomingPerson.fromJson(Map<String, dynamic> json) {
    return LeaveUpcomingPerson(
      employeeId: _toInt(json['employee_id']),
      name: _toText(json['employee_name'] ?? json['name']),
      departmentName: _toText(json['department_name']),
      siteName: _toText(json['site_name']),
    );
  }
}

List<dynamic> _toList(Object? raw) {
  if (raw is List) return raw;
  return const [];
}

List<dynamic> _firstList(List<Object?> candidates) {
  for (final candidate in candidates) {
    final list = _toList(candidate);
    if (list.isNotEmpty) {
      return list;
    }
  }
  return const [];
}

Map<String, dynamic> _firstMap(List<Object?> candidates) {
  for (final candidate in candidates) {
    if (candidate is Map) {
      return candidate.cast<String, dynamic>();
    }
  }
  return const <String, dynamic>{};
}

bool _toBool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final text = _toText(raw).toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

int _toInt(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse(_toText(raw)) ?? 0;
}

String _toText(Object? raw) => (raw ?? '').toString().trim();
