import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/http/api_client.dart';
import '../../core/session.dart';
import '../../core/widgets/kiosk_ui.dart';
import '../../features/required_task/timesheet_sign_off.dart';
import '../../features/status/employee_status.dart';
import '../../features/timesheets/data/timesheet_api.dart';
import '../../features/timesheets/models/timesheet_entry.dart';
import '../../features/timesheets/models/timesheet_week_group.dart';
import '../../features/work/employee_workspace.dart';
import '../../kiosk/idle_countdown.dart';
import '../kiosk_controller.dart';
import '../widgets.dart';

enum _Phase { loading, task, home }

/// Everything shown while an employee is signed in: the header with the
/// sign-out countdown, then any required task, then the home tiles and the
/// feature pages (in their own navigator, so signing out drops them all).
class SignedInShell extends StatefulWidget {
  const SignedInShell({
    super.key,
    required this.controller,
    required this.session,
    this.takePhoto,
    this.today,
  });

  final KioskController controller;
  final AppSession session;
  final PhotoTaker? takePhoto;

  /// For tests; defaults to now.
  final DateTime? today;

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  _Phase _phase = _Phase.loading;
  late AppSession _session = widget.session;
  MobilePermissions? _permissions;
  TimesheetSignOffTask? _task;

  ApiClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final EmployeeStatus status;
    try {
      status = await EmployeeStatusApi(
        session: _session,
        client: _client,
      ).fetch();
    } on ApiException catch (e) {
      if (!mounted || e.isAuthFailure) return;
      widget.controller.abortSignIn(
        e.isNetwork
            ? 'Cannot reach Syncro Connect. Check the tablet is online and try again.'
            : e.message,
      );
      return;
    } catch (_) {
      if (!mounted) return;
      widget.controller.abortSignIn(
        'Sign-in could not finish. Please try again.',
      );
      return;
    }
    if (!mounted) return;
    _session = _session.copyWith(
      employeeFirstName: status.firstName.isEmpty ? null : status.firstName,
      employeeLastName: status.lastName.isEmpty ? null : status.lastName,
      employeeDisplayName: status.displayName.isEmpty
          ? null
          : status.displayName,
    );
    TimesheetSignOffTask? task;
    try {
      task = await loadRequiredSignOff(
        permissions: status.permissions,
        api: TimesheetApi(session: _session, client: _client),
        today: widget.today ?? DateTime.now(),
      );
    } on ApiException {
      return; // Session ended; the controller has signed out.
    }
    if (!mounted) return;
    setState(() {
      _permissions = status.permissions;
      _task = task;
      _phase = task == null ? _Phase.home : _Phase.task;
    });
  }

  void _signOut() => unawaited(widget.controller.signOut());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: KioskFit(
          child: Column(
            children: [
              _Header(
                session: _session,
                idle: widget.controller.idle,
                onSignOut: _signOut,
              ),
              const Divider(height: 1),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.task:
        return RequiredSignOffView(
          task: _task!,
          api: TimesheetApi(session: _session, client: _client),
          onDone: (message) {
            setState(() => _phase = _Phase.home);
            if (message != null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
            }
          },
        );
      case _Phase.home:
        return Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: EmployeeWorkspace(
                session: _session,
                client: _client,
                permissions: _permissions!,
                onSignOut: _signOut,
                takePhoto: widget.takePhoto,
              ),
            ),
          ),
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.idle,
    required this.onSignOut,
  });

  final AppSession session;
  final IdleCountdown idle;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: kGreen,
            child: Text(
              session.initials,
              style: const TextStyle(
                color: kInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              session.fullName,
              key: const Key('header-name'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: idle.remaining,
            builder: (context, seconds, _) {
              final warn = seconds <= 15;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                key: const Key('idle-pill'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: warn ? const Color(0xFFFFF7ED) : kBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: warn ? kAmber : kLine, width: 2),
                ),
                child: Text(
                  'Signing out in ${formatCountdown(seconds)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: warn ? const Color(0xFFB45309) : kMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              key: const Key('sign-out'),
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Confirm your hours for (week)". Continue stays locked until the hours
/// are confirmed; "Something is wrong" goes on without confirming (the
/// server has no way to raise a query from here).
class RequiredSignOffView extends StatefulWidget {
  const RequiredSignOffView({
    super.key,
    required this.task,
    required this.api,
    required this.onDone,
  });

  final TimesheetSignOffTask task;
  final TimesheetApi api;
  final void Function(String? message) onDone;

  @override
  State<RequiredSignOffView> createState() => _RequiredSignOffViewState();
}

class _RequiredSignOffViewState extends State<RequiredSignOffView> {
  bool _busy = false;
  bool _confirmed = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy || _confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final id in widget.task.sessionIds) {
        await widget.api.approve(id);
      }
      if (!mounted) return;
      setState(() => _confirmed = true);
    } on ApiException catch (e) {
      if (e.isAuthFailure || !mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Could not confirm your hours. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final rows = [...task.rows]
      ..sort((a, b) => a.workDate.compareTo(b.workDate));
    final groups = groupTimesheetEntriesByWeek(rows);
    final total = groups.isEmpty ? '00:00' : groups.first.payableLabel;
    final locked = _busy || _confirmed;

    final Widget status;
    if (_confirmed) {
      status = const Row(
        children: [
          Icon(Icons.check_circle, color: kKioskPositive, size: 30),
          SizedBox(width: 12),
          Flexible(
            child: Text(
              'Thank you. Your hours are confirmed.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    } else if (_error != null) {
      status = KioskInlineError(_error!);
    } else {
      status = const Text(
        'Confirm your hours, or tell us something is wrong, to carry on.',
        style: TextStyle(fontSize: 18, color: kKioskMuted),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Confirm your hours for ${task.week.label}',
            key: const Key('required-task-title'),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: kKioskText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Check last week\'s hours before you carry on.',
            style: TextStyle(fontSize: 18, color: kKioskMuted),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: KioskPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final perRow = rows.isEmpty
                            ? 1
                            : rows.length > 7
                            ? 7
                            : rows.length;
                        const gap = 12.0;
                        final width =
                            (constraints.maxWidth - gap * (perRow - 1)) /
                            perRow;
                        return SingleChildScrollView(
                          child: Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (var i = 0; i < rows.length; i++)
                                SizedBox(
                                  width: width,
                                  child: _DayTile(
                                    key: Key('task-day-$i'),
                                    entry: rows[i],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Text('Total paid hours', style: kKioskLabel),
                      const SizedBox(width: 14),
                      Text(
                        total,
                        key: const Key('task-total'),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: kKioskText,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 250,
                        height: 72,
                        child: OutlinedButton.icon(
                          key: const Key('task-wrong'),
                          onPressed: locked
                              ? null
                              : () => widget.onDone(
                                  'Your hours have not been confirmed. Please speak to your manager.',
                                ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kKioskLine, width: 2),
                            textStyle: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.report_outlined, size: 26),
                          label: const Text('Something is wrong'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 250,
                        height: 72,
                        child: FilledButton.icon(
                          key: const Key('task-confirm'),
                          onPressed: locked
                              ? null
                              : () => unawaited(_confirm()),
                          style: FilledButton.styleFrom(
                            textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          icon: _busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 26),
                          label: const Text('Confirm hours'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 20),
              SizedBox(
                width: kKioskSidePanelWidth,
                height: 80,
                child: FilledButton.icon(
                  key: const Key('task-continue'),
                  onPressed: _confirmed ? () => widget.onDone(null) : null,
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: Icon(
                    _confirmed
                        ? Icons.arrow_forward_rounded
                        : Icons.lock_outline_rounded,
                    size: 26,
                  ),
                  label: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One day of the week being confirmed: day, clock-in to clock-out, hours.
class _DayTile extends StatelessWidget {
  const _DayTile({super.key, required this.entry});

  final TimesheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(entry.workDate.trim());
    final hasSpan =
        entry.clockIn.trim().isNotEmpty || entry.clockOut.trim().isNotEmpty;
    final span = hasSpan
        ? '${entry.clockIn.trim().isEmpty ? '--:--' : entry.clockIn} – '
              '${entry.clockOut.trim().isEmpty ? '--:--' : entry.clockOut}'
        : (entry.absenceLabel ?? 'No clocking');
    return Container(
      height: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: entry.requiresApproval ? const Color(0xFFFBFDF7) : kKioskBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: entry.requiresApproval ? kKioskGreen : kKioskLine,
          width: entry.requiresApproval ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            date == null ? entry.dayLabel : shortDay(date).split(' ').first,
            style: kKioskLabel,
          ),
          Text(
            date == null ? '' : '${date.day} ${shortDay(date).split(' ').last}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: kKioskText,
            ),
          ),
          const Spacer(),
          Text(span, style: const TextStyle(fontSize: 17, color: kKioskText)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              entry.totalHours,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: kKioskInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
