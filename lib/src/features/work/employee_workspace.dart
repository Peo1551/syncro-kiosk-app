// The employee app's "My Work" tab (features/home/presentation/home_page.dart,
// _userMenuTab and the pages it opens), lifted out of HomePage for the kiosk.
// Clocking, manager, location, notifications, profile and offline queue code
// is left behind. Page bodies are copied as they are in the employee app so the
// two look and behave the same.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/http/api_client.dart';
import '../../core/session.dart';
import '../../core/widgets/app_modal.dart';
import '../flexi/data/flexi_api.dart';
import '../flexi/models/flexi_summary.dart';
import '../flexi/presentation/my_flexi_page.dart';
import '../leave/data/leave_api.dart';
import '../leave/data/leave_entitlement_api.dart';
import '../leave/models/leave_attachment.dart';
import '../leave/models/leave_config.dart';
import '../leave/models/leave_entitlement.dart';
import '../leave/models/leave_request.dart';
import '../leave/models/leave_upcoming.dart';
import '../status/employee_status.dart';
import '../timesheets/data/timesheet_api.dart';
import '../timesheets/models/timesheet_entry.dart';
import '../timesheets/models/timesheet_week_group.dart';
import 'feature_visibility.dart';
import 'request_sent_page.dart';

enum _TimesheetRangePreset { thisMonth, last7Days, last30Days, custom }

/// Takes a photo for a leave attachment. Injected so tests need no camera.
typedef PhotoTaker = Future<LeaveAttachment?> Function();

class EmployeeWorkspace extends StatefulWidget {
  const EmployeeWorkspace({
    super.key,
    required this.session,
    required this.client,
    required this.permissions,
    required this.onSignOut,
    this.takePhoto,
  });

  final AppSession session;
  final ApiClient client;
  final MobilePermissions permissions;
  final VoidCallback onSignOut;
  final PhotoTaker? takePhoto;

  @override
  State<EmployeeWorkspace> createState() => EmployeeWorkspaceState();
}

class EmployeeWorkspaceState extends State<EmployeeWorkspace> {
  final ValueNotifier<int> _menuDetailRevision = ValueNotifier<int>(0);
  late final LeaveApi _leaveApi;
  late final LeaveEntitlementApi _leaveEntitlementApi;
  late final FlexiApi _flexiApi;
  late final TimesheetApi _timesheetApi;

  List<LeaveGroupOption> _leaveGroups = const [];
  List<LeaveRequest> _leaveRequests = const [];
  LeaveUpcomingViews? _upcomingLeaveViews;
  List<TimesheetEntry> _timesheetRows = const [];
  LeaveEntitlement? _leaveEntitlement;
  FlexiSummary? _flexiSummary;
  bool _flexiLoading = true;
  String? _leaveError;
  String? _upcomingLeaveError;
  String? _entitlementError;
  String? _timesheetError;
  bool _leaveLoading = true;
  bool _upcomingLeaveLoading = true;
  bool _entitlementLoading = true;
  bool _timesheetLoading = false;
  bool _timesheetLoaded = false;
  bool _leaveSubmitting = false;
  int? _leaveActionRequestId;

  final TextEditingController _leaveNotesCtrl = TextEditingController();
  DateTime? _leaveDateFrom;
  DateTime? _leaveDateTo;
  String? _selectedLeaveGroupId;
  int? _selectedLeaveSubtypeId;
  String _selectedDayPart = 'FULL';
  TimeOfDay? _leaveTimeFrom;
  TimeOfDay? _leaveTimeTo;
  LeaveAttachment? _leaveAttachment;
  DateTime _timesheetDateFrom = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime _timesheetDateTo = DateTime.now();
  _TimesheetRangePreset _timesheetRangePreset = _TimesheetRangePreset.thisMonth;

  static const int _maxLeaveAttachmentBytes = 10 * 1024 * 1024;

  List<KioskFeature> get features => visibleFeatures(
    permissions: widget.permissions,
    flexi: _flexiSummary,
  );

  bool get _attachmentsAllowed => widget.permissions.allowAttachment;

  @override
  void initState() {
    super.initState();
    _leaveApi = LeaveApi(session: widget.session, client: widget.client);
    _leaveEntitlementApi = LeaveEntitlementApi(
      session: widget.session,
      client: widget.client,
    );
    _flexiApi = FlexiApi(session: widget.session, client: widget.client);
    _timesheetApi = TimesheetApi(
      session: widget.session,
      client: widget.client,
    );
    unawaited(_refreshAll());
  }

  @override
  void dispose() {
    _leaveNotesCtrl.dispose();
    _menuDetailRevision.dispose();
    super.dispose();
  }

  void _bumpMenuDetailRevision() {
    if (!mounted) return;
    _menuDetailRevision.value = _menuDetailRevision.value + 1;
  }

  /// The API client has already ended the kiosk session for these.
  Future<bool> _handleAuthException(ApiException error) async {
    return error.isAuthFailure;
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshLeave(showLoader: true),
      _refreshEntitlement(showLoader: true),
      _refreshFlexi(),
    ]);
  }

  // ------------------------------------------------------------------ leave

  LeaveGroupOption? get _selectedLeaveGroup {
    final id = _selectedLeaveGroupId;
    if (id == null) return null;
    for (final group in _leaveGroups) {
      if (group.groupId == id) return group;
    }
    return null;
  }

  List<LeaveSubtypeOption> _subtypesForGroup(LeaveGroupOption group) {
    if (group.subtypes.isEmpty) return const [];
    if (!group.allowAlternateSubtypes) {
      final defaultSubtype = group.defaultSubtype;
      if (defaultSubtype != null) return [defaultSubtype];
      return [group.subtypes.first];
    }
    final allowed = group.subtypes.where((s) => s.isSelectable).toList();
    if (allowed.isNotEmpty) return allowed;
    return group.subtypes;
  }

  LeaveSubtypeOption? get _selectedLeaveSubtype {
    final group = _selectedLeaveGroup;
    if (group == null) return null;
    final subtypeId = _selectedLeaveSubtypeId;
    final candidates = _subtypesForGroup(group);
    if (subtypeId != null) {
      for (final subtype in candidates) {
        if (subtype.subtypeId == subtypeId) return subtype;
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  LeavePartDayEligibility _partDayEligibilityForGroup(LeaveGroupOption? group) {
    if (group == null) {
      return const LeavePartDayEligibility(
        allowed: false,
        reason: 'daily_entitlement_mode',
      );
    }
    return leavePartDayEligibility(
      groupRef: group.groupRef,
      requestMode: group.mode,
      entitlementUnit: _leaveEntitlement?.unit,
    );
  }

  bool _usesTimeRangeForSelection(LeaveGroupOption? group) {
    return _selectedDayPart == 'PART' &&
        _partDayEligibilityForGroup(group).allowed;
  }

  List<String> _dayPartOptionsForGroup(LeaveGroupOption? group) {
    final options = <String>['FULL', 'AM', 'PM'];
    if (_partDayEligibilityForGroup(group).allowed) {
      options.add('PART');
    }
    return options;
  }

  String _selectedDayPartForGroup(LeaveGroupOption? group) {
    final selected = _normalizedSelectedDayPartForUi();
    final options = _dayPartOptionsForGroup(group);
    return options.contains(selected) ? selected : 'FULL';
  }

  bool _isAttachmentRequiredForSelection() {
    final group = _selectedLeaveGroup;
    final subtype = _selectedLeaveSubtype;
    final subtypeRule = subtype?.attachmentRequired ?? false;
    final groupRule = group?.attachmentRequired ?? false;
    return subtypeRule || groupRule;
  }

  Future<void> _refreshLeave({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) {
      setState(() {
        _leaveLoading = true;
        _upcomingLeaveLoading = true;
        _leaveError = null;
        _upcomingLeaveError = null;
      });
      _bumpMenuDetailRevision();
    }
    try {
      final snapshotFuture = _leaveApi.fetch();
      final upcomingViewsFuture = _leaveApi.fetchUpcomingViews();
      // Both run together; a failure of either is read below.
      unawaited(snapshotFuture.then((_) {}, onError: (Object _) {}));
      unawaited(upcomingViewsFuture.then((_) {}, onError: (Object _) {}));

      final snapshot = await snapshotFuture;
      LeaveUpcomingViews? upcomingViews = _upcomingLeaveViews;
      String? upcomingError;
      try {
        upcomingViews = await upcomingViewsFuture;
      } on ApiException catch (e) {
        if (await _handleAuthException(e)) return;
        upcomingError = e.message;
      } catch (_) {
        upcomingError = 'Could not load team/company leave.';
      }
      if (!mounted) return;
      setState(() {
        _leaveGroups = snapshot.groups;
        _leaveRequests = snapshot.requests;
        _upcomingLeaveViews = upcomingViews;
        _leaveError = null;
        _upcomingLeaveError = upcomingError;

        if (_leaveGroups.isEmpty) {
          _selectedLeaveGroupId = null;
          _selectedLeaveSubtypeId = null;
        } else {
          final selectedGroupExists = _leaveGroups.any(
            (g) => g.groupId == _selectedLeaveGroupId,
          );
          if (!selectedGroupExists) {
            _selectedLeaveGroupId = _leaveGroups.first.groupId;
          }
          final activeGroup = _selectedLeaveGroup;
          if (activeGroup == null) {
            _selectedLeaveSubtypeId = null;
          } else {
            final subtypes = _subtypesForGroup(activeGroup);
            if (subtypes.isEmpty) {
              _selectedLeaveSubtypeId = null;
            } else {
              final selectedSubtypeExists = subtypes.any(
                (s) => s.subtypeId == _selectedLeaveSubtypeId,
              );
              if (!selectedSubtypeExists) {
                _selectedLeaveSubtypeId =
                    (activeGroup.defaultSubtype ?? subtypes.first).subtypeId;
              }
            }
          }
        }
      });
      _bumpMenuDetailRevision();
    } on ApiException catch (e) {
      if (await _handleAuthException(e)) return;
      if (!mounted) return;
      setState(() => _leaveError = e.message);
      _bumpMenuDetailRevision();
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaveError = 'Could not load leave config.');
      _bumpMenuDetailRevision();
    } finally {
      if (mounted && showLoader) {
        setState(() {
          _leaveLoading = false;
          _upcomingLeaveLoading = false;
        });
        _bumpMenuDetailRevision();
      }
    }
  }

  Future<void> _refreshEntitlement({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) {
      setState(() {
        _entitlementLoading = true;
        _entitlementError = null;
      });
      _bumpMenuDetailRevision();
    }
    try {
      final summary = await _leaveEntitlementApi.fetch();
      if (!mounted) return;
      setState(() {
        _leaveEntitlement = summary;
        _entitlementError = null;
      });
      _bumpMenuDetailRevision();
    } on ApiException catch (e) {
      if (await _handleAuthException(e)) return;
      if (!mounted) return;
      if (_shouldUseEntitlementFallback(e)) {
        setState(() {
          _leaveEntitlement = _fallbackEntitlementSummary();
          _entitlementError = null;
        });
      } else {
        setState(() => _entitlementError = e.message);
      }
      _bumpMenuDetailRevision();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leaveEntitlement = _fallbackEntitlementSummary();
        _entitlementError = null;
      });
      _bumpMenuDetailRevision();
    } finally {
      if (mounted && showLoader) {
        setState(() => _entitlementLoading = false);
        _bumpMenuDetailRevision();
      }
    }
  }

  /// My Flexi is optional: an older server, an error or "not on Flexi" all
  /// mean no tile, and nothing else on the page changes.
  Future<void> _refreshFlexi() async {
    FlexiSummary? summary;
    try {
      summary = await _flexiApi.fetchSummary();
    } catch (_) {
      summary = null;
    }
    if (!mounted) return;
    setState(() {
      _flexiSummary = FlexiSummary.shouldShow(summary) ? summary : null;
      _flexiLoading = false;
    });
    _bumpMenuDetailRevision();
  }

  LeaveGroupOption? get _flexiLeaveGroup {
    for (final group in _leaveGroups) {
      if (group.groupRef.trim().toUpperCase() == 'FLX') return group;
    }
    return null;
  }

  void _selectLeaveGroup(String groupId) {
    _selectedLeaveGroupId = groupId;
    final nextGroup = _selectedLeaveGroup;
    final nextSubtypes = nextGroup == null
        ? const <LeaveSubtypeOption>[]
        : _subtypesForGroup(nextGroup);
    _selectedLeaveSubtypeId = nextSubtypes.isEmpty
        ? null
        : (nextGroup!.defaultSubtype ?? nextSubtypes.first).subtypeId;
    _selectedDayPart = 'FULL';
    _leaveTimeFrom = null;
    _leaveTimeTo = null;
    _leaveError = null;
  }

  void _openFlexiLeaveRequest(BuildContext pageContext) {
    final group = _flexiLeaveGroup;
    if (group == null) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Flexi leave cannot be requested here yet. Please speak to your manager.',
          ),
        ),
      );
      return;
    }
    if (!_leaveSubmitting) {
      setState(() => _selectLeaveGroup(group.groupId));
      _bumpMenuDetailRevision();
    }
    _openMenuPage(
      title: 'Request Leave',
      builder: (requestContext) => _userTab(requestContext),
    );
  }

  Widget _myFlexiTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    return MyFlexiView(
      summary: _flexiSummary,
      loading: _flexiLoading,
      onRefresh: _refreshFlexi,
      onRequestFlexiLeave: () => _openFlexiLeaveRequest(pageContext),
    );
  }

  LeaveEntitlement _fallbackEntitlementSummary() {
    return LeaveEntitlement.fallbackFromRequests(
      requests: _leaveRequests,
      referenceDate: DateTime.now(),
    );
  }

  bool _shouldUseEntitlementFallback(ApiException e) {
    final code = e.statusCode ?? 0;
    if (code == 0 || code == 404 || code == 408 || code >= 500) {
      return true;
    }

    final message = e.message.trim().toLowerCase();
    if (message.isEmpty) {
      return true;
    }
    return message == 'request failed' ||
        message == 'unexpected response from server.' ||
        message.startsWith('server returned an unexpected response:') ||
        message.startsWith('holiday summary failed:') ||
        message.contains('timed out');
  }

  // ------------------------------------------------------------- timesheets

  Future<void> _refreshTimesheets({bool showLoader = true}) async {
    if (!mounted) return;
    final rangeError = _validateTimesheetRange(
      _timesheetDateFrom,
      _timesheetDateTo,
    );
    if (rangeError != null) {
      setState(() {
        _timesheetError = rangeError;
        _timesheetLoading = false;
      });
      _bumpMenuDetailRevision();
      return;
    }
    if (showLoader) {
      setState(() {
        _timesheetLoading = true;
        _timesheetError = null;
      });
      _bumpMenuDetailRevision();
    }
    try {
      final rows = await _timesheetApi.fetch(
        from: _timesheetDateFrom,
        to: _timesheetDateTo,
      );
      if (!mounted) return;
      setState(() {
        _timesheetRows = rows;
        _timesheetError = null;
        _timesheetLoaded = true;
      });
      _bumpMenuDetailRevision();
    } on ApiException catch (e) {
      if (await _handleAuthException(e)) return;
      if (!mounted) return;
      setState(() => _timesheetError = e.message);
      _bumpMenuDetailRevision();
    } catch (_) {
      if (!mounted) return;
      setState(() => _timesheetError = 'Could not load timesheet.');
      _bumpMenuDetailRevision();
    } finally {
      if (mounted && showLoader) {
        setState(() => _timesheetLoading = false);
        _bumpMenuDetailRevision();
      }
    }
  }

  DateTimeRange _timesheetRangeForPreset(_TimesheetRangePreset preset) {
    final today = _dateOnly(DateTime.now());
    switch (preset) {
      case _TimesheetRangePreset.last7Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case _TimesheetRangePreset.last30Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case _TimesheetRangePreset.thisMonth:
        return DateTimeRange(
          start: DateTime(today.year, today.month),
          end: today,
        );
      case _TimesheetRangePreset.custom:
        return DateTimeRange(start: _timesheetDateFrom, end: _timesheetDateTo);
    }
  }

  DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String? _validateTimesheetRange(DateTime from, DateTime to) {
    final start = _dateOnly(from);
    final end = _dateOnly(to);
    if (end.isBefore(start)) {
      return 'Date range end must be on or after start.';
    }
    if (end.difference(start).inDays > 366) {
      return 'Date range is limited to 366 days.';
    }
    return null;
  }

  String _timesheetRangePresetLabel(_TimesheetRangePreset preset) {
    switch (preset) {
      case _TimesheetRangePreset.thisMonth:
        return 'This month';
      case _TimesheetRangePreset.last7Days:
        return 'Last 7 days';
      case _TimesheetRangePreset.last30Days:
        return 'Last 30 days';
      case _TimesheetRangePreset.custom:
        return 'Custom';
    }
  }

  void _applyTimesheetRange(DateTimeRange range, _TimesheetRangePreset preset) {
    final start = _dateOnly(range.start);
    final end = _dateOnly(range.end);
    final rangeError = _validateTimesheetRange(start, end);
    setState(() {
      if (rangeError == null) {
        _timesheetDateFrom = start;
        _timesheetDateTo = end;
        _timesheetRangePreset = preset;
      }
      _timesheetError = rangeError;
    });
    _bumpMenuDetailRevision();
  }

  Future<void> _selectTimesheetRangePreset(
    BuildContext pickerContext,
    _TimesheetRangePreset preset,
  ) async {
    if (preset == _TimesheetRangePreset.custom) {
      await _pickTimesheetRange(pickerContext);
      return;
    }
    _applyTimesheetRange(_timesheetRangeForPreset(preset), preset);
    await _refreshTimesheets(showLoader: true);
  }

  // ------------------------------------------------------------ leave form

  Future<void> _pickLeaveRange(BuildContext pickerContext) async {
    final initialFrom = _leaveDateFrom ?? _leaveDateTo ?? DateTime.now();
    final initialTo = _leaveDateTo ?? _leaveDateFrom ?? initialFrom;
    final picked = await showDateRangePicker(
      context: pickerContext,
      initialDateRange: DateTimeRange(
        start: initialFrom,
        end: initialTo.isBefore(initialFrom) ? initialFrom : initialTo,
      ),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _leaveDateFrom = picked.start;
      _leaveDateTo = picked.end;
    });
    _bumpMenuDetailRevision();
  }

  Future<void> _pickLeaveTime(
    BuildContext pickerContext, {
    required bool from,
  }) async {
    final initial = from
        ? (_leaveTimeFrom ?? const TimeOfDay(hour: 9, minute: 0))
        : (_leaveTimeTo ?? const TimeOfDay(hour: 17, minute: 0));
    final picked = await showTimePicker(
      context: pickerContext,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _leaveTimeFrom = picked;
      } else {
        _leaveTimeTo = picked;
      }
    });
    _bumpMenuDetailRevision();
  }

  Widget _buildLeaveTimeRangeControls(BuildContext pageContext) {
    String fmtTimeButton(TimeOfDay? time) {
      if (time == null) return '--:--';
      return _fmtTime(time);
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _leaveSubmitting
                ? null
                : () => _pickLeaveTime(pageContext, from: true),
            child: Text('From time: ${fmtTimeButton(_leaveTimeFrom)}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: _leaveSubmitting
                ? null
                : () => _pickLeaveTime(pageContext, from: false),
            child: Text('To time: ${fmtTimeButton(_leaveTimeTo)}'),
          ),
        ),
      ],
    );
  }

  /// Kiosk: camera only. A shared tablet must not offer its file store, and
  /// the photo is read into memory and its temporary file deleted at once.
  Future<LeaveAttachment?> _pickAttachment(BuildContext routeContext) async {
    final custom = widget.takePhoto;
    if (custom != null) return custom();
    try {
      final captured = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );
      if (captured == null) return null;
      final bytes = await captured.readAsBytes();
      if (!kIsWeb) {
        try {
          await File(captured.path).delete();
        } catch (_) {}
      }
      if (!mounted || !routeContext.mounted) return null;
      return _finalizeAttachment(
        routeContext,
        fileName: _cameraAttachmentName(captured.name),
        bytes: bytes,
      );
    } catch (_) {
      if (!mounted || !routeContext.mounted) return null;
      _showAttachmentMessage(routeContext, 'Could not open the camera.');
      return null;
    }
  }

  LeaveAttachment? _finalizeAttachment(
    BuildContext routeContext, {
    required String fileName,
    required Uint8List? bytes,
  }) {
    final name = fileName.trim();
    if (name.isEmpty || bytes == null || bytes.isEmpty) {
      _showAttachmentMessage(routeContext, 'Could not read the captured photo.');
      return null;
    }
    if (bytes.length > _maxLeaveAttachmentBytes) {
      _showAttachmentMessage(routeContext, 'Attachment must be 10MB or less.');
      return null;
    }
    return LeaveAttachment(
      fileName: name,
      bytes: bytes,
      sizeBytes: bytes.length,
    );
  }

  String _cameraAttachmentName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isNotEmpty &&
        trimmed.contains('.') &&
        const ['jpg', 'jpeg', 'png'].contains(
          trimmed.split('.').last.toLowerCase(),
        )) {
      return trimmed;
    }
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'leave_$stamp.jpg';
  }

  void _showAttachmentMessage(BuildContext routeContext, String message) {
    if (!mounted || !routeContext.mounted) return;
    ScaffoldMessenger.of(
      routeContext,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _normalizedSelectedDayPartForUi([String? raw]) {
    final value = (raw ?? _selectedDayPart).trim().toUpperCase();
    if (value == 'PART' || value == 'PART_DAY' || value == 'TIME') {
      return 'PART';
    }
    return normalizeLeaveDayPart(value);
  }

  String _dayPartLabel(String dayPart) {
    switch (dayPart) {
      case 'AM':
        return 'First half';
      case 'PM':
        return 'Second half';
      case 'PART':
        return 'Part day';
      case 'FULL':
      default:
        return 'Full day';
    }
  }

  int? _leaveMinutesOfDay(TimeOfDay? time) {
    if (time == null) return null;
    return time.hour * 60 + time.minute;
  }

  String? _validateLeaveForm() {
    final group = _selectedLeaveGroup;
    if (group == null) return 'No leave groups available.';
    final subtype = _selectedLeaveSubtype;
    if (subtype == null) return 'No leave subtype is available for this group.';
    final from = _leaveDateFrom;
    final to = _leaveDateTo;
    if (from == null || to == null) return 'Select a date range.';
    if (to.isBefore(from)) return 'Date range is invalid.';

    if (_normalizedSelectedDayPartForUi() == 'PART') {
      final eligibility = _partDayEligibilityForGroup(group);
      if (!eligibility.allowed) {
        return eligibility.denialMessage;
      }
      if (!leavePartDayIsSingleDate(from, to)) {
        return 'Part day can only be booked for one date.';
      }
      final timeValidation = validateLeavePartDayTimeRange(
        _leaveMinutesOfDay(_leaveTimeFrom),
        _leaveMinutesOfDay(_leaveTimeTo),
      );
      if (!timeValidation.valid) {
        return timeValidation.message;
      }
    }

    if (_isAttachmentRequiredForSelection() && _leaveAttachment == null) {
      return 'Attachment is required for this leave type.';
    }
    return null;
  }

  Future<void> _submitLeaveRequest(BuildContext pageContext) async {
    if (_leaveSubmitting) return;
    final error = _validateLeaveForm();
    if (error != null) {
      setState(() => _leaveError = error);
      _bumpMenuDetailRevision();
      return;
    }

    final group = _selectedLeaveGroup!;
    final subtype = _selectedLeaveSubtype!;
    final dateFrom = _leaveDateFrom!;
    final dateTo = _leaveDateTo!;
    final useTimeRange = _usesTimeRangeForSelection(group);
    final dayPart = _selectedDayPartForGroup(group);

    setState(() {
      _leaveSubmitting = true;
      _leaveError = null;
    });
    _bumpMenuDetailRevision();
    try {
      await _leaveApi.create(
        LeaveCreateInput(
          dateFrom: dateFrom,
          dateTo: dateTo,
          groupId: group.groupId,
          groupRef: group.groupRef,
          subtypeId: subtype.subtypeId,
          dayPart: dayPart,
          timeFrom: useTimeRange ? _fmtTime(_leaveTimeFrom!) : null,
          timeTo: useTimeRange ? _fmtTime(_leaveTimeTo!) : null,
          notes: _leaveNotesCtrl.text.trim(),
          attachment: _leaveAttachment,
        ),
      );
      if (!mounted) return;
      setState(() {
        _leaveDateFrom = null;
        _leaveDateTo = null;
        _leaveTimeFrom = null;
        _leaveTimeTo = null;
        _selectedDayPart = 'FULL';
        _leaveNotesCtrl.clear();
        _leaveAttachment = null;
      });
      _bumpMenuDetailRevision();
      _showRequestSent();
      unawaited(_refreshLeave(showLoader: false));
      unawaited(_refreshEntitlement(showLoader: false));
      unawaited(_refreshFlexi());
    } on ApiException catch (e) {
      if (await _handleAuthException(e)) return;
      if (!mounted) return;
      setState(() => _leaveError = e.message);
      _bumpMenuDetailRevision();
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaveError = 'Could not submit leave request.');
      _bumpMenuDetailRevision();
    } finally {
      if (mounted) {
        setState(() => _leaveSubmitting = false);
        _bumpMenuDetailRevision();
      }
    }
  }

  /// Kiosk: a sent request ends on its own screen with a short sign-out
  /// countdown, so the next person does not find this employee signed in.
  void _showRequestSent() {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => RequestSentPage(
          onDoSomethingElse: () =>
              navigator.popUntil((route) => route.isFirst),
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  Future<void> _cancelLeaveRequest(
    BuildContext routeContext,
    LeaveRequest request,
  ) async {
    if (_leaveActionRequestId != null) return;
    setState(() {
      _leaveActionRequestId = request.requestId;
      _leaveError = null;
    });
    _bumpMenuDetailRevision();
    try {
      await _leaveApi.cancel(request.requestId);
      await _refreshLeave(showLoader: false);
      await _refreshEntitlement(showLoader: false);
      await _refreshFlexi();
      if (!mounted || !routeContext.mounted) return;
      ScaffoldMessenger.of(
        routeContext,
      ).showSnackBar(const SnackBar(content: Text('Leave request cancelled.')));
    } on ApiException catch (e) {
      if (await _handleAuthException(e)) return;
      if (!mounted) return;
      setState(() => _leaveError = e.message);
      _bumpMenuDetailRevision();
      if (routeContext.mounted) {
        ScaffoldMessenger.of(
          routeContext,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaveError = 'Could not cancel leave request.');
      _bumpMenuDetailRevision();
    } finally {
      if (mounted) {
        setState(() => _leaveActionRequestId = null);
        _bumpMenuDetailRevision();
      }
    }
  }

  Future<void> _requestLeaveRemoval(
    BuildContext routeContext,
    LeaveRequest request,
  ) async {
    if (_leaveActionRequestId != null) return;
    final draft = await _showRemovalRequestDialog(routeContext);
    if (draft == null || !mounted) return;

    setState(() {
      _leaveActionRequestId = request.requestId;
      _leaveError = null;
    });
    _bumpMenuDetailRevision();
    try {
      await _leaveApi.requestRemoval(
        requestId: request.requestId,
        reason: draft.reason,
        attachment: draft.attachment,
      );
      await _refreshLeave(showLoader: false);
      await _refreshEntitlement(showLoader: false);
      await _refreshFlexi();
      if (!mounted || !routeContext.mounted) return;
      ScaffoldMessenger.of(routeContext).showSnackBar(
        const SnackBar(content: Text('Removal request submitted.')),
      );
    } on ApiException catch (e) {
      if (await _handleAuthException(e)) return;
      if (!mounted) return;
      setState(() => _leaveError = e.message);
      _bumpMenuDetailRevision();
      if (routeContext.mounted) {
        ScaffoldMessenger.of(
          routeContext,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaveError = 'Could not submit removal request.');
      _bumpMenuDetailRevision();
    } finally {
      if (mounted) {
        setState(() => _leaveActionRequestId = null);
        _bumpMenuDetailRevision();
      }
    }
  }

  Future<_RemovalRequestDraft?> _showRemovalRequestDialog(
    BuildContext routeContext,
  ) {
    return showAppDialog<_RemovalRequestDraft>(
      context: routeContext,
      builder: (_) => _RemovalRequestDialog(
        onPickAttachment: _attachmentsAllowed
            ? () => _pickAttachment(routeContext)
            : null,
      ),
    );
  }

  String _fmtDateForButton(DateTime? dt) {
    if (dt == null) return '--/--/----';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$d/$m/$y';
  }

  String _fmtTime(TimeOfDay time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _statusChip(String text) {
    final lower = text.toLowerCase();
    final approved = lower.contains('approved') || lower.contains('complete');
    final pending =
        lower.contains('pending') || lower.contains('removal pending');
    final rejected = lower.contains('rejected') || lower.contains('cancelled');
    final color = rejected
        ? const Color(0xFFEF4444)
        : pending
        ? const Color(0xFFF59E0B)
        : approved
        ? const Color(0xFF8FD3A3)
        : const Color(0xFFD7E0EA);
    final bg = rejected
        ? const Color(0xFFFFEBEE)
        : pending
        ? const Color(0xFFFFF7EA)
        : approved
        ? const Color(0xFFEAF8EF)
        : const Color(0xFFF3F6FA);
    return Chip(
      label: Text(text),
      side: BorderSide(color: color),
      backgroundColor: bg,
      visualDensity: VisualDensity.compact,
    );
  }

  // ------------------------------------------------------- Request Leave

  Widget _userTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final theme = Theme.of(pageContext);
    final group = _selectedLeaveGroup;
    final subtypeOptions = group == null
        ? const <LeaveSubtypeOption>[]
        : _subtypesForGroup(group);
    final useTimeRange = _usesTimeRangeForSelection(group);
    final dayPartOptions = _dayPartOptionsForGroup(group);
    final selectedDayPart = _selectedDayPartForGroup(group);
    final partDayEligibility = _partDayEligibilityForGroup(group);
    final subtypeLocked = group != null && !group.allowAlternateSubtypes;
    final attachmentRequired = _isAttachmentRequiredForSelection();
    final showAttachment = _attachmentsAllowed || attachmentRequired;
    final pendingRequests = _leaveRequests.where(_isPendingRequest).toList();

    return RefreshIndicator(
      onRefresh: _refreshLeave,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_leaveLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_leaveGroups.isEmpty)
                    Text(
                      'No leave groups available. Contact your manager.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE8B7)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x110F172A),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF97CC33),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.event_available_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Request leave',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  showAttachment
                                      ? 'Choose the type, set the dates, and add a photo if needed.'
                                      : 'Choose the type and set the dates.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF7B8794),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Leave type',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const Key('leave-group'),
                      initialValue: _selectedLeaveGroupId,
                      decoration: const InputDecoration(
                        labelText: 'Group',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _leaveGroups
                          .map(
                            (g) => DropdownMenuItem<String>(
                              value: g.groupId,
                              child: Text(g.name),
                            ),
                          )
                          .toList(),
                      onChanged: _leaveSubmitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _selectLeaveGroup(value));
                              _bumpMenuDetailRevision();
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('leave-subtype-$_selectedLeaveGroupId'),
                      initialValue: _selectedLeaveSubtypeId,
                      decoration: const InputDecoration(
                        labelText: 'Subtype',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: subtypeOptions
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: s.subtypeId,
                              child: Text(s.name),
                            ),
                          )
                          .toList(),
                      onChanged:
                          (_leaveSubmitting ||
                              subtypeLocked ||
                              subtypeOptions.isEmpty)
                          ? null
                          : (value) {
                              setState(() => _selectedLeaveSubtypeId = value);
                              _bumpMenuDetailRevision();
                            },
                    ),
                    if (group != null &&
                        group.groupRef.trim().toUpperCase() == 'FLX' &&
                        FlexiSummary.shouldShow(_flexiSummary)) ...[
                      const SizedBox(height: 12),
                      FlexiRequestBalanceNote(summary: _flexiSummary!),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Dates',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        key: const Key('leave-dates'),
                        onPressed: _leaveSubmitting
                            ? null
                            : () => _pickLeaveRange(pageContext),
                        child: Text(
                          'Date range: ${_fmtDateForButton(_leaveDateFrom)} to ${_fmtDateForButton(_leaveDateTo)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_leaveDateFrom != null || _leaveDateTo != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBEF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD7E9AF)),
                        ),
                        child: Text(
                          'Selected dates: ${_fmtDateForButton(_leaveDateFrom)} to ${_fmtDateForButton(_leaveDateTo)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF47611F),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<String>(
                      key: ValueKey('leave-daypart-$_selectedLeaveGroupId'),
                      initialValue: selectedDayPart,
                      decoration: const InputDecoration(
                        labelText: 'Day part',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: dayPartOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(_dayPartLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: _leaveSubmitting
                          ? null
                          : (value) => setState(() {
                              if (value != null) {
                                _selectedDayPart = value;
                                if (value != 'PART') {
                                  _leaveTimeFrom = null;
                                  _leaveTimeTo = null;
                                }
                                _leaveError = null;
                              }
                              _bumpMenuDetailRevision();
                            }),
                    ),
                    if (!partDayEligibility.allowed &&
                        partDayEligibility.reason != 'daily_entitlement_mode' &&
                        group?.groupRef.trim().toUpperCase() == 'HOL') ...[
                      const SizedBox(height: 6),
                      Text(
                        partDayEligibility.denialMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (useTimeRange) ...[
                      const SizedBox(height: 8),
                      _buildLeaveTimeRangeControls(pageContext),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      showAttachment ? 'Notes & attachment' : 'Notes',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _leaveNotesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Add any context your manager should see.',
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    if (showAttachment) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _leaveAttachment == null
                                    ? 'No photo added'
                                    : _leaveAttachment!.fileName,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_leaveAttachment != null)
                              TextButton(
                                onPressed: _leaveSubmitting
                                    ? null
                                    : () {
                                        setState(() => _leaveAttachment = null);
                                        _bumpMenuDetailRevision();
                                      },
                                child: const Text('Remove'),
                              ),
                            TextButton(
                              onPressed: _leaveSubmitting
                                  ? null
                                  : () async {
                                      final picked = await _pickAttachment(
                                        pageContext,
                                      );
                                      if (picked == null || !mounted) return;
                                      setState(() => _leaveAttachment = picked);
                                      _bumpMenuDetailRevision();
                                    },
                              child: Text(
                                _leaveAttachment == null
                                    ? 'Take photo'
                                    : 'Retake',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attachmentRequired
                            ? 'A photo is required for this selection.'
                            : 'Photo optional (max 10MB).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: attachmentRequired
                              ? const Color(0xFFB45309)
                              : const Color(0xFF6B7280),
                          fontWeight: attachmentRequired
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                  if (_leaveError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _leaveError!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      key: const Key('leave-submit'),
                      onPressed:
                          (_leaveSubmitting ||
                              _leaveLoading ||
                              _leaveGroups.isEmpty)
                          ? null
                          : () => _submitLeaveRequest(pageContext),
                      child: _leaveSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Pending requests', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_leaveLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pendingRequests.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No pending requests.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          else
            ...pendingRequests.map(
              (request) => _buildLeaveRequestCard(pageContext, request),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ Request History

  Widget _requestHistoryTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final pending = _leaveRequests
        .where((request) => request.isRequested && _isPendingRequest(request))
        .toList();
    final approved = _leaveRequests
        .where((request) => request.isRequested && _isApprovedRequest(request))
        .toList();
    final rejected = _leaveRequests
        .where((request) => request.isRequested && _isRejectedRequest(request))
        .toList();

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _leaveRequestList(
                  pageContext,
                  rows: pending,
                  emptyMessage: 'No pending requests yet.',
                ),
                _leaveRequestList(
                  pageContext,
                  rows: approved,
                  emptyMessage: 'No approved requests yet.',
                  useHistoryStatusLabel: true,
                ),
                _leaveRequestList(
                  pageContext,
                  rows: rejected,
                  emptyMessage: 'No rejected requests yet.',
                  allowActions: false,
                  useHistoryStatusLabel: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- Upcoming Leave

  List<LeaveRequest> _upcomingLeaveRows() {
    final rows = _leaveRequests.where((request) {
      final startDate = _parseIsoDate(request.dateFrom);
      final endDate = _parseIsoDate(request.dateTo) ?? startDate;
      if (startDate == null || endDate == null) return false;
      if (!_isInUpcomingWindow(startDate, endDate)) {
        return false;
      }
      return request.keepsLeaveBooked;
    }).toList();
    rows.sort((a, b) {
      final aStart = _parseIsoDate(a.dateFrom) ?? _parseIsoDate(a.dateTo);
      final bStart = _parseIsoDate(b.dateFrom) ?? _parseIsoDate(b.dateTo);
      if (aStart == null && bStart == null) return 0;
      if (aStart == null) return 1;
      if (bStart == null) return -1;
      final byStart = aStart.compareTo(bStart);
      if (byStart != 0) return byStart;
      final aEnd = _parseIsoDate(a.dateTo) ?? aStart;
      final bEnd = _parseIsoDate(b.dateTo) ?? bStart;
      return aEnd.compareTo(bEnd);
    });
    return rows;
  }

  List<LeaveUpcomingEntry> _filterSharedUpcomingRows(
    List<LeaveUpcomingEntry> rows,
  ) {
    return rows.where((entry) {
      final startDate = _parseIsoDate(entry.dateFrom);
      final endDate = _parseIsoDate(entry.dateTo) ?? startDate;
      if (startDate == null || endDate == null) {
        return false;
      }
      return _isInUpcomingWindow(startDate, endDate);
    }).toList();
  }

  bool _isInUpcomingWindow(DateTime startDate, DateTime endDate) {
    final today = DateTime.now();
    final windowStart = DateTime(today.year, today.month, today.day);
    final windowEndExclusive = _addMonths(windowStart, 12);
    return !endDate.isBefore(windowStart) &&
        startDate.isBefore(windowEndExclusive);
  }

  DateTime _addMonths(DateTime value, int monthsToAdd) {
    final totalMonths = (value.year * 12) + value.month - 1 + monthsToAdd;
    final year = totalMonths ~/ 12;
    final month = (totalMonths % 12) + 1;
    final day = math.min(value.day, DateTime(year, month + 1, 0).day);
    return DateTime(
      year,
      month,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  Widget _upcomingTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final rows = _upcomingLeaveRows();
    final upcomingViews = _upcomingLeaveViews;
    final tabs = <Tab>[const Tab(text: 'My Leave')];
    final views = <Widget>[
      _leaveRequestList(
        pageContext,
        rows: rows,
        emptyMessage: 'No upcoming leave booked in the next 12 months.',
      ),
    ];

    if (upcomingViews?.canViewTeam == true) {
      tabs.add(const Tab(text: 'My Team'));
      views.add(
        _sharedUpcomingLeaveList(
          pageContext,
          rows: _filterSharedUpcomingRows(upcomingViews?.team ?? const []),
          emptyMessage:
              'No upcoming leave is booked for your team in the next 12 months.',
        ),
      );
    }

    if (upcomingViews?.canViewCompany == true) {
      tabs.add(const Tab(text: 'Company'));
      views.add(
        _sharedUpcomingLeaveList(
          pageContext,
          rows: _filterSharedUpcomingRows(upcomingViews?.company ?? const []),
          emptyMessage:
              'No upcoming leave is booked across the company in the next 12 months.',
        ),
      );
    }

    if (tabs.length == 1) {
      return views.first;
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(tabs: tabs),
          Expanded(child: TabBarView(children: views)),
        ],
      ),
    );
  }

  Widget _sharedUpcomingLeaveList(
    BuildContext viewContext, {
    required List<LeaveUpcomingEntry> rows,
    required String emptyMessage,
  }) {
    return RefreshIndicator(
      onRefresh: _refreshLeave,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_upcomingLeaveLoading && _upcomingLeaveViews == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if ((_upcomingLeaveError ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _upcomingLeaveError!,
                      style: Theme.of(viewContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(viewContext).colorScheme.error,
                          ),
                    ),
                  ),
                ),
              ),
            if (rows.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    emptyMessage,
                    style: Theme.of(viewContext).textTheme.bodySmall,
                  ),
                ),
              )
            else
              ...rows.map(
                (entry) => _buildSharedUpcomingCard(viewContext, entry),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSharedUpcomingCard(
    BuildContext viewContext,
    LeaveUpcomingEntry entry,
  ) {
    final people = entry.people;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.dateRangeText,
                      style: Theme.of(viewContext).textTheme.titleMedium,
                    ),
                  ),
                  _statusChip(
                    entry.count == 1 ? '1 person' : '${entry.count} people',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Type: ${entry.typeLabel}'),
              Text('Day part: ${entry.dayPartLabel}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: people.map((person) {
                  final subtitleParts = <String>[
                    if (person.departmentName.trim().isNotEmpty)
                      person.departmentName.trim(),
                    if (person.siteName.trim().isNotEmpty)
                      person.siteName.trim(),
                  ];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name.trim().isEmpty ? 'Employee' : person.name,
                          style: Theme.of(viewContext).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (subtitleParts.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitleParts.join(' • '),
                            style: Theme.of(viewContext).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------- My Entitlement

  Widget _myEntitlementTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final theme = Theme.of(pageContext);
    final entitlement = _leaveEntitlement;
    return RefreshIndicator(
      onRefresh: _refreshEntitlement,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _entitlementLoading
                  ? const Center(child: CircularProgressIndicator())
                  : entitlement == null && _entitlementError != null
                  ? Text(
                      _entitlementError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : entitlement == null
                  ? Text(
                      'No entitlement data available.',
                      style: theme.textTheme.bodySmall,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entitlement.isFallback) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFFBBF24),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.info_outline,
                                    color: Color(0xFFD97706),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Showing a default entitlement estimate while the live summary service is unavailable.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF9A3412),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ] else if (_entitlementError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Text(
                              'Latest refresh failed: $_entitlementError',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE8F8D0), Color(0xFFF7FBF1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFD9E8B8)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Remaining balance',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF52606D),
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          entitlement.balanceLabel,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontSize: 34,
                                                color: entitlement.balance < 0
                                                    ? const Color(0xFFDC2626)
                                                    : const Color(0xFF1A9C44),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.beach_access_rounded,
                                      color: Color(0xFF84B01F),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                entitlement.isFallback
                                    ? 'Estimated from approved holiday already visible for ${entitlement.yearStart} to ${entitlement.yearEnd}.'
                                    : entitlement.needsSetup
                                    ? 'Default allowance currently shown for ${entitlement.yearStart} to ${entitlement.yearEnd} while setup completes.'
                                    : 'Live balance for ${entitlement.yearStart} to ${entitlement.yearEnd}.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Holiday fuel gauge',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 18,
                            value: entitlement.progressValue,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Booked ${entitlement.bookedLabel}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Left ${entitlement.balanceLabel}',
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: entitlement.balance < 0
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF1A9C44),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _entitlementMetricCard(
                              pageContext,
                              title: 'Entitlement',
                              value: entitlement.totalLabel,
                              valueColor: const Color(0xFF0F172A),
                            ),
                            _entitlementMetricCard(
                              pageContext,
                              title: 'Booked',
                              value: entitlement.bookedLabel,
                              valueColor: const Color(0xFFB45309),
                            ),
                            _entitlementMetricCard(
                              pageContext,
                              title: 'Balance',
                              value: entitlement.balanceLabel,
                              valueColor: entitlement.balance < 0
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF1A9C44),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ My Clocking Hub

  Widget _myClockingHubTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final theme = Theme.of(pageContext);
    final rateSummaries = _timesheetRateSummaries();
    final weeklyGroups = groupTimesheetEntriesByWeek(_timesheetRows);
    return RefreshIndicator(
      onRefresh: _refreshTimesheets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date range', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _TimesheetRangePreset.values.map((preset) {
                      return ChoiceChip(
                        label: Text(_timesheetRangePresetLabel(preset)),
                        selected: _timesheetRangePreset == preset,
                        onSelected: _timesheetLoading
                            ? null
                            : (_) => _selectTimesheetRangePreset(
                                pageContext,
                                preset,
                              ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => _pickTimesheetRange(pageContext),
                      child: Text(
                        'Date range: ${_fmtDateForButton(_timesheetDateFrom)} to ${_fmtDateForButton(_timesheetDateTo)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _timesheetLoading
                          ? null
                          : () => _refreshTimesheets(showLoader: true),
                      child: const Text('Load timesheet'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _timesheetLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _timesheetError != null
                  ? Text(
                      _timesheetError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : _timesheetRows.isEmpty
                  ? Text(
                      'No timesheet rows available for this date range.',
                      style: theme.textTheme.bodySmall,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (rateSummaries.isNotEmpty) ...[
                          Text(
                            'Rate totals for this range',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: rateSummaries.map((summary) {
                              return _timesheetRateSummaryChip(
                                pageContext,
                                summary,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          'Tap total hours to view the rate breakdown for that day.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...weeklyGroups.expand(
                          (group) => [
                            _timesheetWeekSummary(pageContext, group),
                            const SizedBox(height: 10),
                            timesheetHeaderRow(pageContext),
                            const SizedBox(height: 8),
                            ...group.entries.map(
                              (entry) => buildTimesheetRow(
                                pageContext,
                                entry,
                                onShowBreakdown: _showRateBreakdown,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTimesheetRange(BuildContext pickerContext) async {
    final picked = await showDateRangePicker(
      context: pickerContext,
      initialDateRange: DateTimeRange(
        start: _timesheetDateFrom,
        end: _timesheetDateTo,
      ),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    _applyTimesheetRange(picked, _TimesheetRangePreset.custom);
    await _refreshTimesheets(showLoader: true);
  }

  Widget _timesheetWeekSummary(
    BuildContext viewContext,
    TimesheetWeekGroup group,
  ) {
    final theme = Theme.of(viewContext);
    final varianceLabel = group.hasCompleteScheduledTarget
        ? group.varianceMinutes > 0
              ? 'Over'
              : group.varianceMinutes < 0
              ? 'Short'
              : 'Variance'
        : 'Variance';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text('Paid ${group.payableLabel}'),
              Text('Scheduled ${group.scheduledLabel}'),
              Text('$varianceLabel ${group.varianceLabel}'),
            ],
          ),
        ],
      ),
    );
  }

  List<_TimesheetRateSummary> _timesheetRateSummaries() {
    final totals = <String, int>{};
    final usageCounts = <String, int>{};
    for (final entry in _timesheetRows) {
      final labelsSeen = <String>{};
      for (final rate in entry.rates) {
        final label = rate.label.trim().isEmpty ? 'Rate' : rate.label.trim();
        totals.update(
          label,
          (value) => value + rate.minutes,
          ifAbsent: () => rate.minutes,
        );
        labelsSeen.add(label);
      }
      for (final label in labelsSeen) {
        usageCounts.update(label, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    final rows = totals.entries
        .map(
          (entry) => _TimesheetRateSummary(
            label: entry.key,
            minutes: entry.value,
            uses: usageCounts[entry.key] ?? 0,
          ),
        )
        .toList();
    rows.sort((a, b) {
      final byMinutes = b.minutes.compareTo(a.minutes);
      if (byMinutes != 0) return byMinutes;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return rows;
  }

  Widget _timesheetRateSummaryChip(
    BuildContext viewContext,
    _TimesheetRateSummary summary,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.label,
            style: Theme.of(
              viewContext,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            summary.hhmm,
            style: Theme.of(
              viewContext,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (summary.uses > 0) ...[
            const SizedBox(height: 2),
            Text(
              summary.useLabel,
              style: Theme.of(
                viewContext,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRateBreakdown(
    BuildContext routeContext,
    TimesheetEntry entry,
  ) {
    return showModalBottomSheet<void>(
      context: routeContext,
      showDragHandle: true,
      builder: (ctx) {
        return AppSheetPanel(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rate breakdown',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(entry.dayLabel, style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _timesheetDetailMetric(
                        ctx,
                        label: 'Total',
                        value: entry.totalHours,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _timesheetDetailMetric(
                        ctx,
                        label: 'Scheduled',
                        value: entry.hasScheduledTarget
                            ? _minutesToHhmm(entry.scheduledMinutes)
                            : '--:--',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _timesheetDetailMetric(
                        ctx,
                        label: entry.isOvertimeDay
                            ? 'Over'
                            : entry.isUnderTargetDay
                            ? 'Short'
                            : 'Variance',
                        value: entry.varianceLabel ?? '00:00',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...entry.rates.map((rate) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(rate.label)),
                        Text(
                          rate.hhmm,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }),
                if (entry.absenceDetails.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'Paid leave',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ...entry.absenceDetails.map((detail) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(detail.displayLabel),
                                if (detail.hasDistinctType)
                                  Text(
                                    detail.type,
                                    style: Theme.of(ctx).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            detail.hhmm,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timesheetDetailMetric(
    BuildContext viewContext, {
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              viewContext,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              viewContext,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _minutesToHhmm(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hours = safeMinutes ~/ 60;
    final remainder = safeMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------- shared leave cards

  Widget _leaveRequestList(
    BuildContext viewContext, {
    required List<LeaveRequest> rows,
    required String emptyMessage,
    bool allowActions = true,
    bool useHistoryStatusLabel = false,
  }) {
    return RefreshIndicator(
      onRefresh: _refreshLeave,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_leaveLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  emptyMessage,
                  style: Theme.of(viewContext).textTheme.bodySmall,
                ),
              ),
            )
          else
            ...rows.map(
              (request) => _buildLeaveRequestCard(
                viewContext,
                request,
                allowActions: allowActions,
                useHistoryStatusLabel: useHistoryStatusLabel,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeaveRequestCard(
    BuildContext viewContext,
    LeaveRequest request, {
    bool allowActions = true,
    bool useHistoryStatusLabel = false,
  }) {
    final actionBusy = _leaveActionRequestId == request.requestId;
    final showActions = allowActions && !request.isHistoryRejected;
    final showCancelAction =
        showActions && request.canCancel && !request.hasPendingRemovalWorkflow;
    final showRemovalAction =
        showActions &&
        request.canRequestRemoval &&
        !request.hasPendingRemovalWorkflow;
    final statusLabel = useHistoryStatusLabel
        ? request.historyStatusLabel
        : request.activeStatusLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.dateRangeText,
                      style: Theme.of(viewContext).textTheme.titleMedium,
                    ),
                  ),
                  _statusChip(statusLabel),
                ],
              ),
              const SizedBox(height: 6),
              Text('Group: ${request.groupName}'),
              Text(
                'Subtype: ${request.subtypeName.isEmpty ? '-' : request.subtypeName}',
              ),
              Text('Day part: ${request.dayPartLabel}'),
              if ((request.timeRangeText ?? '').isNotEmpty)
                Text('Time: ${request.timeRangeText}'),
              if (request.hasAttachment) const Text('Attachment: Included'),
              if ((request.removalStatusText ?? '').isNotEmpty)
                Text('Removal: ${request.removalStatusText}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (showCancelAction)
                    OutlinedButton(
                      onPressed: actionBusy
                          ? null
                          : () => _cancelLeaveRequest(viewContext, request),
                      child: actionBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Cancel'),
                    ),
                  if (showRemovalAction) ...[
                    if (showCancelAction) const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: actionBusy
                          ? null
                          : () => _requestLeaveRemoval(viewContext, request),
                      child: const Text('Request removal'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entitlementMetricCard(
    BuildContext viewContext, {
    required String title,
    required String value,
    required Color valueColor,
  }) {
    return SizedBox(
      width: 150,
      height: 78,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                viewContext,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(viewContext).textTheme.titleMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isApprovedRequest(LeaveRequest request) => request.isHistoryApproved;

  bool _isRejectedRequest(LeaveRequest request) => request.isHistoryRejected;

  bool _isPendingRequest(LeaveRequest request) => request.isPendingWorkflow;

  DateTime? _parseIsoDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  void _openMenuPage({required String title, required WidgetBuilder builder}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MenuDetailPage(
          title: title,
          builder: builder,
          refreshListenable: _menuDetailRevision,
        ),
      ),
    );
  }

  void openFeature(KioskFeature feature) {
    switch (feature) {
      case KioskFeature.requestLeave:
        _openMenuPage(
          title: 'Request Leave',
          builder: (pageContext) => _userTab(pageContext),
        );
      case KioskFeature.requestHistory:
        _openMenuPage(
          title: 'Request History',
          builder: (pageContext) => _requestHistoryTab(pageContext),
        );
      case KioskFeature.upcomingLeave:
        _openMenuPage(
          title: 'Upcoming Leave',
          builder: (pageContext) => _upcomingTab(pageContext),
        );
      case KioskFeature.myEntitlement:
        _openMenuPage(
          title: 'My Entitlement',
          builder: (pageContext) => _myEntitlementTab(pageContext),
        );
      case KioskFeature.myClockingHub:
        if (!_timesheetLoaded && !_timesheetLoading) {
          unawaited(_refreshTimesheets(showLoader: true));
        }
        _openMenuPage(
          title: 'My Clocking Hub',
          builder: (pageContext) => _myClockingHubTab(pageContext),
        );
      case KioskFeature.myFlexi:
        _openMenuPage(
          title: 'My Flexi',
          builder: (pageContext) => _myFlexiTab(pageContext),
        );
    }
  }

  // ------------------------------------------------------------------ home

  _TileInfo _tileFor(KioskFeature feature) {
    final requestedRows = _leaveRequests
        .where((request) => request.isRequested)
        .toList();
    final pendingCount = requestedRows.where(_isPendingRequest).length;
    final approvedCount = requestedRows.where(_isApprovedRequest).length;
    final rejectedCount = requestedRows.where(_isRejectedRequest).length;
    final upcomingCount = _upcomingLeaveRows().length;
    final entitlementBalance = _entitlementLoading
        ? 'Loading...'
        : _leaveEntitlement?.balanceLabel ?? 'Unavailable';
    switch (feature) {
      case KioskFeature.requestLeave:
        return _TileInfo(
          icon: Icons.beach_access_outlined,
          title: 'Request Leave',
          subtitle: pendingCount > 0
              ? 'Submit a new leave request. $pendingCount pending ${pendingCount == 1 ? 'request is' : 'requests are'} waiting.'
              : 'Submit a new leave request.',
        );
      case KioskFeature.requestHistory:
        return _TileInfo(
          icon: Icons.assignment_outlined,
          title: 'Request History',
          subtitle:
              'Pending: $pendingCount. Approved: $approvedCount. Rejected: $rejectedCount.',
        );
      case KioskFeature.upcomingLeave:
        return _TileInfo(
          icon: Icons.event_available_outlined,
          title: 'Upcoming Leave',
          subtitle: upcomingCount > 0
              ? '$upcomingCount ${upcomingCount == 1 ? 'booking' : 'bookings'} in the next 12 months.'
              : 'See upcoming leave for the next 12 months.',
        );
      case KioskFeature.myEntitlement:
        return _TileInfo(
          icon: Icons.insights_outlined,
          title: 'My Entitlement',
          subtitle: _entitlementLoading
              ? 'Loading entitlement summary...'
              : 'Current balance: $entitlementBalance.',
        );
      case KioskFeature.myClockingHub:
        return const _TileInfo(
          icon: Icons.schedule_outlined,
          title: 'My Clocking Hub',
          subtitle: 'Your clocking records and hours.',
        );
      case KioskFeature.myFlexi:
        final balance = _flexiSummary?.balance;
        return _TileInfo(
          icon: Icons.timelapse_outlined,
          title: 'My Flexi',
          subtitle: balance == null
              ? 'Your Flexi balance.'
              : 'Balance: ${balance.text}.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = features;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : 2;
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          children: [
            Text(
              'What would you like to do?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.3,
              children: [
                for (final feature in tiles)
                  _FeatureTile(
                    key: Key('tile-${feature.name}'),
                    info: _tileFor(feature),
                    onTap: () => openFeature(feature),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TileInfo {
  const _TileInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({super.key, required this.info, required this.onTap});

  final _TileInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE6E8EE)),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5DA),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(info.icon, size: 30, color: const Color(0xFF102F08)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

/// Timesheet table header, shared with the required sign-off screen.
Widget timesheetHeaderRow(BuildContext viewContext) {
  TextStyle style() => Theme.of(
    viewContext,
  ).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700);
  return Row(
    children: [
      Expanded(flex: 3, child: Text('Day', style: style())),
      Expanded(flex: 2, child: Text('Paid in', style: style())),
      Expanded(flex: 2, child: Text('Paid out', style: style())),
      Expanded(flex: 2, child: Text('Total hours', style: style())),
    ],
  );
}

/// One timesheet day, as in the employee app's Clocking Hub.
Widget buildTimesheetRow(
  BuildContext viewContext,
  TimesheetEntry entry, {
  Future<void> Function(BuildContext, TimesheetEntry)? onShowBreakdown,
}) {
  final isOvertime = entry.isOvertimeDay;
  final isUnderTarget = entry.isUnderTargetDay;
  final absenceLabel = entry.absenceLabel;
  final showAbsenceLabel = entry.shouldShowAbsenceLabelInline;
  final rowFill = isOvertime
      ? const Color(0xFFE9F9EE)
      : isUnderTarget
      ? const Color(0xFFFFECEC)
      : Colors.white;
  final rowBorder = isOvertime
      ? const Color(0xFF9ACC3B)
      : isUnderTarget
      ? const Color(0xFFE57373)
      : const Color(0xFFE2E8F0);
  final canBreakdown = entry.hasRateBreakdown && onShowBreakdown != null;
  final totalTextStyle = TextStyle(
    color: canBreakdown ? const Color(0xFF0F766E) : const Color(0xFF1E2433),
    fontWeight: FontWeight.w700,
    decoration: canBreakdown ? TextDecoration.underline : null,
  );
  final total = canBreakdown
      ? InkWell(
          onTap: () => onShowBreakdown(viewContext, entry),
          child: Text(entry.totalHours, style: totalTextStyle),
        )
      : Text(entry.totalHours, style: totalTextStyle);

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: rowFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: rowBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.dayLabel),
              if (entry.status.trim().isNotEmpty)
                Text(
                  entry.status,
                  style: Theme.of(viewContext).textTheme.bodySmall,
                ),
              if (showAbsenceLabel)
                Text(
                  absenceLabel!,
                  style: Theme.of(viewContext).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (entry.varianceLabel != null)
                Text(
                  entry.isOvertimeDay
                      ? 'Over target ${entry.varianceLabel}'
                      : 'Under target ${entry.varianceLabel}',
                  style: Theme.of(viewContext).textTheme.bodySmall?.copyWith(
                    color: entry.isOvertimeDay
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFB91C1C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        Expanded(flex: 2, child: Text(entry.clockIn)),
        Expanded(flex: 2, child: Text(entry.clockOut)),
        Expanded(flex: 2, child: total),
      ],
    ),
  );
}

class _MenuDetailPage extends StatelessWidget {
  const _MenuDetailPage({
    required this.title,
    required this.builder,
    required this.refreshListenable,
  });

  final String title;
  final WidgetBuilder builder;
  final ValueListenable<int> refreshListenable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        leadingWidth: 132,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: TextButton.icon(
            key: const Key('page-back'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ),
        title: Text(title),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: refreshListenable,
        builder: (context, _, _) => SafeArea(child: builder(context)),
      ),
    );
  }
}

class _RemovalRequestDraft {
  const _RemovalRequestDraft({required this.reason, this.attachment});

  final String reason;
  final LeaveAttachment? attachment;
}

class _TimesheetRateSummary {
  const _TimesheetRateSummary({
    required this.label,
    required this.minutes,
    required this.uses,
  });

  final String label;
  final int minutes;
  final int uses;

  String get hhmm {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  String get useLabel => uses == 1 ? 'Used on 1 day' : 'Used on $uses days';
}

class _RemovalRequestDialog extends StatefulWidget {
  const _RemovalRequestDialog({required this.onPickAttachment});

  /// Null when the employee's group does not allow attachments.
  final Future<LeaveAttachment?> Function()? onPickAttachment;

  @override
  State<_RemovalRequestDialog> createState() => _RemovalRequestDialogState();
}

class _RemovalRequestDialogState extends State<_RemovalRequestDialog> {
  final TextEditingController _reasonCtrl = TextEditingController();

  LeaveAttachment? _attachment;
  String? _error;
  bool _pickingAttachment = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAttachmentPick() async {
    final pick = widget.onPickAttachment;
    if (pick == null) return;
    setState(() => _pickingAttachment = true);
    try {
      final picked = await pick();
      if (!mounted || picked == null) return;
      setState(() {
        _attachment = picked;
        _error = null;
      });
    } finally {
      if (mounted) {
        setState(() => _pickingAttachment = false);
      }
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }

    Navigator.of(
      context,
    ).pop(_RemovalRequestDraft(reason: reason, attachment: _attachment));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppDialogPanel(
      title: 'Request removal',
      description:
          'Tell your manager why this approved leave should be removed.',
      icon: Icons.assignment_late_outlined,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Submit')),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _reasonCtrl,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Add a short reason for the removal request',
              alignLabelWithHint: true,
            ),
            onChanged: (_) {
              if (_error == null) return;
              setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (widget.onPickAttachment != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _attachment == null
                              ? 'No photo added'
                              : 'Photo ready',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _attachment?.fileName ??
                              'Optional photo, max 10MB.',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _pickingAttachment
                        ? null
                        : _handleAttachmentPick,
                    child: _pickingAttachment
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_attachment == null ? 'Take photo' : 'Retake'),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
