// The employee app's "My Work" tab (features/home/presentation/home_page.dart,
// _userMenuTab and the pages it opens), lifted out of HomePage for the kiosk.
// Clocking, manager, location, notifications, profile and offline queue code
// is left behind. The data loading, validation and API calls are the employee
// app's; the pages themselves (in views/) are laid out for a landscape tablet.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/http/api_client.dart';
import '../../core/session.dart';
import '../../core/widgets/app_modal.dart';
import '../../core/widgets/kiosk_ui.dart';
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

part 'views/request_leave_view.dart';
part 'views/leave_lists_view.dart';
part 'views/entitlement_view.dart';
part 'views/clocking_hub_view.dart';

enum _HistoryFilter { all, pending, approved, rejected }

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
  DateTime _timesheetDateFrom = _mondayOf(DateTime.now());
  late DateTime _timesheetDateTo = DateTime(
    _timesheetDateFrom.year,
    _timesheetDateFrom.month,
    _timesheetDateFrom.day + 6,
  );
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  int? _selectedHistoryRequestId;
  int _upcomingView = 0;
  int? _selectedUpcomingIndex;
  int? _selectedTimesheetIndex;

  static const int _maxLeaveAttachmentBytes = 10 * 1024 * 1024;

  List<KioskFeature> get features =>
      visibleFeatures(permissions: widget.permissions, flexi: _flexiSummary);

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

  /// setState for the open feature page as well as this widget.
  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _bumpMenuDetailRevision();
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
        _selectedTimesheetIndex = null;
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

  static DateTime _mondayOf(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  bool get _timesheetOnCurrentWeek =>
      !_timesheetDateFrom.isBefore(_mondayOf(DateTime.now()));

  /// Moves the Clocking Hub by whole weeks (Monday to Sunday) and reloads.
  Future<void> _shiftTimesheetWeek(int weeks) async {
    final start = DateTime(
      _timesheetDateFrom.year,
      _timesheetDateFrom.month,
      _timesheetDateFrom.day + 7 * weeks,
    );
    final end = DateTime(start.year, start.month, start.day + 6);
    final rangeError = _validateTimesheetRange(start, end);
    _set(() {
      if (rangeError == null) {
        _timesheetDateFrom = start;
        _timesheetDateTo = end;
      }
      _timesheetError = rangeError;
    });
    if (rangeError != null) return;
    await _refreshTimesheets(showLoader: true);
  }

  Future<void> _showCurrentTimesheetWeek() {
    final weeks =
        _mondayOf(DateTime.now()).difference(_timesheetDateFrom).inDays ~/ 7;
    return _shiftTimesheetWeek(weeks);
  }

  // ------------------------------------------------------------ leave form

  Future<void> _pickLeaveDate(
    BuildContext pickerContext, {
    required bool from,
  }) async {
    final now = DateTime.now();
    final firstDate = now.subtract(const Duration(days: 365));
    final lastDate = now.add(const Duration(days: 365 * 3));
    final current = from ? _leaveDateFrom : _leaveDateTo;
    final picked = await showKioskDatePicker(
      context: pickerContext,
      initialDate: current ?? _leaveDateFrom ?? _leaveDateTo ?? now,
      firstDate: from ? firstDate : (_leaveDateFrom ?? firstDate),
      lastDate: lastDate,
      helpText: from ? 'First day of leave' : 'Last day of leave',
    );
    if (picked == null || !mounted) return;
    _set(() {
      if (from) {
        _leaveDateFrom = picked;
        final to = _leaveDateTo;
        if (to == null || to.isBefore(picked)) _leaveDateTo = picked;
      } else {
        _leaveDateTo = picked;
        _leaveDateFrom ??= picked;
      }
      _leaveError = null;
    });
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
    _set(() {
      if (from) {
        _leaveTimeFrom = picked;
      } else {
        _leaveTimeTo = picked;
      }
    });
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
      _showAttachmentMessage(
        routeContext,
        'Could not read the captured photo.',
      );
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
        const [
          'jpg',
          'jpeg',
          'png',
        ].contains(trimmed.split('.').last.toLowerCase())) {
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
          onDoSomethingElse: () => navigator.popUntil((route) => route.isFirst),
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

  String _fmtTime(TimeOfDay time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
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

  String _minutesToHhmm(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hours = safeMinutes ~/ 60;
    final remainder = safeMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
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
                child: Icon(
                  info.icon,
                  size: 30,
                  color: const Color(0xFF102F08),
                ),
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
      backgroundColor: kKioskBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 76,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      key: const Key('page-back'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: OutlinedButton.styleFrom(
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 26),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      title,
                      key: const Key('page-title'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: kKioskText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Theme(
                data: kioskPageTheme(Theme.of(context)),
                child: ValueListenableBuilder<int>(
                  valueListenable: refreshListenable,
                  builder: (context, _, _) => builder(context),
                ),
              ),
            ),
          ],
        ),
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
                          _attachment?.fileName ?? 'Optional photo, max 10MB.',
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
