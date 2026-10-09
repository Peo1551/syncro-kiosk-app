import 'dart:convert';

import '../../../config/app_config.dart';
import '../../../core/http/api_client.dart';
import '../../../core/session.dart';
import '../models/leave_attachment.dart';
import '../models/leave_config.dart';
import '../models/leave_upcoming.dart';
import '../models/leave_request.dart';

String normalizeLeaveDayPart(String raw) {
  final value = raw.trim().toLowerCase();
  switch (value) {
    case 'am':
    case 'first_half':
      return 'AM';
    case 'pm':
    case 'second_half':
      return 'PM';
    case 'part':
    case 'part_day':
    case 'time':
      return 'PART';
    case 'full':
    case 'full_day':
    case '':
      return 'FULL';
    default:
      return 'FULL';
  }
}

String normalizeLeaveCreateErrorMessage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'Could not submit leave request.';
  }

  final value = trimmed.toLowerCase();
  if (value.contains('duplicate key') ||
      value.contains('unique index') ||
      value.contains('unique constraint') ||
      value.contains('cannot insert duplicate key row') ||
      value.contains('overlaps an existing pending or approved request')) {
    return 'A leave request or booking already exists for those dates. Please check your request history or upcoming leave before submitting another request.';
  }

  return trimmed;
}

String _fmtDate(DateTime dt) {
  final d = dt.toLocal();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

class LeaveSnapshot {
  const LeaveSnapshot({required this.groups, required this.requests});

  final List<LeaveGroupOption> groups;
  final List<LeaveRequest> requests;
}

class LeaveCreateInput {
  const LeaveCreateInput({
    required this.dateFrom,
    required this.dateTo,
    required this.groupId,
    required this.groupRef,
    this.subtypeId,
    required this.dayPart,
    this.timeFrom,
    this.timeTo,
    this.notes,
    this.attachment,
  });

  final DateTime dateFrom;
  final DateTime dateTo;
  final String groupId;
  final String groupRef;
  final int? subtypeId;
  final String dayPart;
  final String? timeFrom;
  final String? timeTo;
  final String? notes;
  final LeaveAttachment? attachment;
}

Map<String, String> buildLeaveCreateFields(LeaveCreateInput input) {
  final normalizedGroupId = input.groupId.trim();
  final normalizedGroupRef = input.groupRef.trim();
  final notes = (input.notes ?? '').trim();
  final dayPart = normalizeLeaveDayPart(input.dayPart);
  final fields = <String, String>{
    'action': 'create',
    'group_id': normalizedGroupId,
    'group_ref': normalizedGroupRef.isEmpty
        ? normalizedGroupId
        : normalizedGroupRef,
    'date_from': _fmtDate(input.dateFrom),
    'date_to': _fmtDate(input.dateTo),
    'day_part': dayPart,
    'start_date': _fmtDate(input.dateFrom),
    'end_date': _fmtDate(input.dateTo),
    'reason': notes,
    'notes': notes,
  };
  if (input.subtypeId != null && input.subtypeId! > 0) {
    fields['subtype_id'] = input.subtypeId!.toString();
    fields['type_id'] = input.subtypeId!.toString();
  }
  final from = (input.timeFrom ?? '').trim();
  final to = (input.timeTo ?? '').trim();
  if (from.isNotEmpty) {
    fields['time_from'] = from;
  }
  if (to.isNotEmpty) {
    fields['time_to'] = to;
  }
  if (dayPart == 'PART') {
    fields['booking_unit'] = 'HOUR';
    fields['hour_mode'] = 'PART';
    fields['all_day'] = '0';
    if (from.isNotEmpty) {
      fields['start_time'] = from;
    }
    if (to.isNotEmpty) {
      fields['end_time'] = to;
    }
  }
  return fields;
}

class LeaveApi {
  const LeaveApi({required AppSession session, required ApiClient client})
    : _session = session,
      _client = client;

  final AppSession _session;
  final ApiClient _client;

  Future<LeaveSnapshot> fetch() async {
    final json = await _client.getJson(
      path: AppConfig.leaveRequestsPath,
      cookieHeader: _session.cookieHeader,
    );
    final groups = _parseGroups(json);
    final requests = _parseRequests(json);
    return LeaveSnapshot(groups: groups, requests: requests);
  }

  Future<LeaveUpcomingViews> fetchUpcomingViews() async {
    final json = await _client.getJson(
      path: AppConfig.leaveUpcomingPath,
      cookieHeader: _session.cookieHeader,
    );
    if (json['ok'] != true) {
      throw ApiException(
        (json['message'] ??
                json['error'] ??
                'Could not load upcoming leave views.')
            .toString(),
      );
    }
    return LeaveUpcomingViews.fromJson(json);
  }

  Future<void> create(LeaveCreateInput input) async {
    try {
      final fields = buildLeaveCreateFields(input);

      final json = await _postMultipart(
        fields: fields,
        attachment: input.attachment,
        attachmentFieldName: 'attachment',
        defaultErrorMessage: 'Could not submit leave request.',
      );
      if (json['ok'] != true) {
        throw ApiException(
          normalizeLeaveCreateErrorMessage(
            (json['message'] ??
                    json['error'] ??
                    'Could not submit leave request.')
                .toString(),
          ),
        );
      }
    } on ApiException catch (e) {
      if (e.isAuthFailure) rethrow;
      throw ApiException(
        normalizeLeaveCreateErrorMessage(e.message),
        statusCode: e.statusCode,
      );
    }
  }

  Future<void> cancel(int requestId) async {
    try {
      final json = await _postMultipart(
        fields: {
          'action': 'cancel',
          'request_id': requestId.toString(),
          'id': requestId.toString(),
        },
        attachment: null,
        attachmentFieldName: 'attachment',
        defaultErrorMessage: 'Could not cancel leave request.',
      );
      if (json['ok'] != true) {
        throw ApiException(
          (json['message'] ??
                  json['error'] ??
                  'Could not cancel leave request.')
              .toString(),
        );
      }
      return;
    } on ApiException catch (error) {
      if (error.isAuthFailure || error.statusCode == 403) rethrow;
      final response = await _client.getRaw(
        path: '${AppConfig.leaveRequestsPath}?id=$requestId&method=delete',
        cookieHeader: _session.cookieHeader,
      );
      final json = _decodeJson(response.body);
      if (response.statusCode >= 400 || json['ok'] != true) {
        throw ApiException(
          (json['message'] ??
                  json['error'] ??
                  'Could not cancel leave request.')
              .toString(),
          statusCode: response.statusCode,
        );
      }
    }
  }

  Future<void> requestRemoval({
    required int requestId,
    required String reason,
    LeaveAttachment? attachment,
  }) async {
    final json = await _postMultipart(
      fields: {
        'action': 'request_removal',
        'request_id': requestId.toString(),
        'reason': reason.trim(),
        'removal_reason': reason.trim(),
      },
      attachment: attachment,
      attachmentFieldName: 'attachment',
      defaultErrorMessage: 'Could not submit removal request.',
    );
    if (json['ok'] != true) {
      throw ApiException(
        (json['message'] ??
                json['error'] ??
                'Could not submit removal request.')
            .toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _postMultipart({
    required Map<String, String> fields,
    required LeaveAttachment? attachment,
    required String attachmentFieldName,
    required String defaultErrorMessage,
  }) async {
    final response = await _client.postMultipart(
      path: AppConfig.leaveRequestsPath,
      cookieHeader: _session.cookieHeader,
      csrfToken: _session.csrf,
      fields: fields,
      file: attachment == null
          ? null
          : MultipartFile(
              fieldName: attachmentFieldName,
              fileName: attachment.fileName,
              contentType: _contentTypeForExtension(attachment.extensionLower),
              bytes: attachment.bytes,
            ),
    );
    final json = _decodeJson(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        (json['message'] ?? json['error'] ?? defaultErrorMessage).toString(),
        statusCode: response.statusCode,
        code: json['code']?.toString(),
        retryAfterSeconds: ApiException.parseRetryAfter(
          response.retryAfter,
          json,
        ),
      );
    }
    return json;
  }

  List<LeaveGroupOption> _parseGroups(Map<String, dynamic> json) {
    var groupsRaw = _toList(json['groups']);
    if (groupsRaw.isEmpty && json['leave_config'] is Map<String, dynamic>) {
      final config = json['leave_config'] as Map<String, dynamic>;
      groupsRaw = _toList(config['groups']);
    }
    if (groupsRaw.isEmpty) {
      groupsRaw = _toList(json['leave_groups']);
    }
    if (groupsRaw.isEmpty && json['config'] is Map<String, dynamic>) {
      final config = json['config'] as Map<String, dynamic>;
      groupsRaw = _toList(config['groups']);
    }

    const allowedRefs = {'HOL', 'SICK', 'ABS', 'TRN', 'OTH'};
    final groups = groupsRaw
        .whereType<Map>()
        .map((row) => LeaveGroupOption.fromJson(row.cast<String, dynamic>()))
        .where(
          (row) =>
              row.groupId.trim().isNotEmpty &&
              row.name.trim().isNotEmpty &&
              allowedRefs.contains(row.groupRef.toUpperCase()),
        )
        .toList();
    if (groups.isNotEmpty) return groups;

    final typesRaw = _toList(json['types']);
    return typesRaw
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .map((row) {
          final typeId = _toInt(row['type_id'] ?? row['id']);
          final name = (row['name'] ?? row['type_name'] ?? '').toString();
          final groupRef = (row['group_ref'] ?? row['group_id'] ?? name)
              .toString()
              .trim()
              .toUpperCase();
          final subtype = LeaveSubtypeOption(
            subtypeId: typeId,
            name: name,
            mode: LeaveMode.dayBased,
            isDefault: true,
            isSelectable: true,
            attachmentRequired: false,
          );
          return LeaveGroupOption(
            groupId: groupRef,
            groupRef: groupRef,
            name: name,
            mode: LeaveMode.dayBased,
            attachmentRequired: false,
            allowAlternateSubtypes: false,
            defaultSubtypeId: typeId,
            subtypes: [subtype],
          );
        })
        .where(
          (row) => row.groupId.trim().isNotEmpty && row.name.trim().isNotEmpty,
        )
        .toList();
  }

  List<LeaveRequest> _parseRequests(Map<String, dynamic> json) {
    var rowsRaw = _toList(json['requests']);
    if (rowsRaw.isEmpty) {
      rowsRaw = _toList(json['rows']);
    }
    if (rowsRaw.isEmpty) {
      rowsRaw = _toList(json['leave_requests']);
    }
    return rowsRaw
        .whereType<Map>()
        .map((row) => LeaveRequest.fromJson(row.cast<String, dynamic>()))
        .where((row) => row.requestId > 0)
        .toList();
  }

  Map<String, dynamic> _decodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'message': 'Unexpected response.'};
    }
  }

  List<dynamic> _toList(Object? raw) {
    if (raw is List) return raw;
    return const [];
  }

  int _toInt(Object? raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString().trim()) ?? 0;
  }

  String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }
}
