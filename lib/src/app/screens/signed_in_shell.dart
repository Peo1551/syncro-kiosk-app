import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/http/api_client.dart';
import '../../core/session.dart';
import '../../features/required_task/timesheet_sign_off.dart';
import '../../features/status/employee_status.dart';
import '../../features/timesheets/data/timesheet_api.dart';
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
      widget.controller.abortSignIn('Sign-in could not finish. Please try again.');
      return;
    }
    if (!mounted) return;
    _session = _session.copyWith(
      employeeFirstName: status.firstName.isEmpty ? null : status.firstName,
      employeeLastName: status.lastName.isEmpty ? null : status.lastName,
      employeeDisplayName: status.displayName.isEmpty ? null : status.displayName,
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
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
      setState(() => _error = 'Could not confirm your hours. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        Text(
          'Confirm your hours for ${task.week.label}',
          key: const Key('required-task-title'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Check last week\'s hours before you carry on.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                timesheetHeaderRow(context),
                const SizedBox(height: 8),
                ...task.rows.map((row) => buildTimesheetRow(context, row)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[ErrorNote(_error!), const SizedBox(height: 12)],
        if (_confirmed)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF8EF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF8FD3A3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF1A9C44)),
                SizedBox(width: 10),
                Text(
                  'Thank you. Your hours are confirmed.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 64,
                child: OutlinedButton(
                  key: const Key('task-wrong'),
                  onPressed: _busy || _confirmed
                      ? null
                      : () => widget.onDone(
                          'Your hours have not been confirmed. Please speak to your manager.',
                        ),
                  child: const Text('Something is wrong'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton(
                  key: const Key('task-confirm'),
                  onPressed: _busy || _confirmed
                      ? null
                      : () => unawaited(_confirm()),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text('Confirm'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton(
                  key: const Key('task-continue'),
                  onPressed: _confirmed ? () => widget.onDone(null) : null,
                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
