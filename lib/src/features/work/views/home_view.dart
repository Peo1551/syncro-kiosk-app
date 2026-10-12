part of '../employee_workspace.dart';

// The signed-in home: a greeting, an at-a-glance strip of the employee's key
// numbers, then the feature tiles filling the rest of the screen. Request
// Leave is the large lime tile on the left; the others share two rows on the
// right so 4, 5 or 6 tiles always fill the grid without gaps or scrolling.
// Every figure comes from the data the workspace already loads.

const _kHomeOrange = Color(0xFFEA6C1A);
const _kHomeAmber = Color(0xFFF59E0B);
const _kHomeBlue = Color(0xFF2563EB);
const _kHomeTeal = Color(0xFF0F766E);
const _kHomePurple = Color(0xFF7C3AED);

/// What a home tile shows: its accent, title and one key fact.
class _HomeTileInfo {
  const _HomeTileInfo({
    required this.icon,
    required this.accent,
    required this.title,
    required this.fact,
    this.sub,
    this.progress,
  });

  final IconData icon;
  final Color accent;
  final String title;

  /// The bold line; null while it is still loading.
  final String? fact;
  final String? sub;
  final double? progress;
}

extension _HomeView on EmployeeWorkspaceState {
  int get _pendingRequestCount =>
      _leaveRequests.where((r) => r.isRequested && _isPendingRequest(r)).length;

  String? get _nextLeaveLabel {
    if (_leaveLoading) return null;
    final rows = _upcomingLeaveRows();
    if (rows.isEmpty) return 'None booked';
    final start = _parseIsoDate(rows.first.dateFrom);
    if (start == null) return 'None booked';
    final today = dateOnly(DateTime.now());
    final day = dateOnly(start);
    return day.isAfter(today) ? shortDay(day) : 'Today';
  }

  String? get _holidayLeftLabel {
    if (_entitlementLoading) return null;
    return _leaveEntitlement?.balanceLabel ?? '—';
  }

  String _greeting(DateTime now) {
    final part = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    var first = widget.session.employeeFirstName.trim();
    if (first.isEmpty) {
      final full = widget.session.fullName.trim();
      first = full == 'Employee' ? '' : full.split(RegExp(r'\s+')).first;
    }
    return first.isEmpty ? part : '$part, $first';
  }

  String _hoursAndMinutes(int minutes) {
    final safe = minutes < 0 ? 0 : minutes;
    final h = safe ~/ 60;
    final m = safe % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  _HomeTileInfo _homeTileFor(KioskFeature feature) {
    switch (feature) {
      case KioskFeature.requestLeave:
        return const _HomeTileInfo(
          icon: Icons.flight_takeoff_rounded,
          accent: kKioskInk,
          title: 'Request Leave',
          fact: 'Book holiday or time off',
        );
      case KioskFeature.requestHistory:
        final requested = _leaveRequests.where((r) => r.isRequested).toList();
        final pending = requested.where(_isPendingRequest).length;
        final approved = requested.where(_isApprovedRequest).length;
        final rejected = requested.where(_isRejectedRequest).length;
        final decided = '$approved approved · $rejected rejected';
        return _HomeTileInfo(
          icon: Icons.history_rounded,
          accent: _kHomeBlue,
          title: 'Request History',
          fact: _leaveLoading
              ? null
              : pending > 0
              ? '$pending pending'
              : requested.isEmpty
              ? 'No requests yet'
              : decided,
          sub: !_leaveLoading && pending > 0 ? decided : null,
        );
      case KioskFeature.upcomingLeave:
        final count = _leaveLoading ? 0 : _upcomingLeaveRows().length;
        final next = _nextLeaveLabel;
        return _HomeTileInfo(
          icon: Icons.event_available_rounded,
          accent: _kHomeTeal,
          title: 'Upcoming Leave',
          fact: next == null
              ? null
              : count == 0
              ? 'None booked'
              : 'Next: $next',
          sub: _leaveLoading
              ? null
              : count == 0
              ? 'Next 12 months'
              : '$count in the next 12 months',
        );
      case KioskFeature.myEntitlement:
        final summary = _leaveEntitlement;
        return _HomeTileInfo(
          icon: Icons.pie_chart_rounded,
          accent: _kHomeOrange,
          title: 'My Entitlement',
          fact: _entitlementLoading
              ? null
              : summary == null
              ? 'Unavailable'
              : '${summary.balanceLabel} left',
          progress: _entitlementLoading || summary == null
              ? null
              : summary.progressValue,
        );
      case KioskFeature.myClockingHub:
        final showWeek =
            _timesheetLoaded &&
            _timesheetError == null &&
            _timesheetOnCurrentWeek;
        final minutes = _timesheetRows.fold<int>(
          0,
          (sum, row) => sum + row.payableMinutes,
        );
        return _HomeTileInfo(
          icon: Icons.access_time_filled_rounded,
          accent: kKioskInk,
          title: 'My Clocking Hub',
          fact: showWeek
              ? '${_hoursAndMinutes(minutes)} this week'
              : 'Your hours this week',
        );
      case KioskFeature.myFlexi:
        final balance = _flexiSummary?.balance;
        return _HomeTileInfo(
          icon: Icons.balance_rounded,
          accent: _kHomePurple,
          title: 'My Flexi',
          fact: balance?.text,
          sub: 'Flexi balance',
        );
    }
  }

  Widget _homeView(BuildContext context) {
    final now = DateTime.now();
    final tiles = features;
    final onFlexi = tiles.contains(KioskFeature.myFlexi);
    return ColoredBox(
      color: kKioskBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: _OneLine(
                    _greeting(now),
                    key: const Key('home-greeting'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: kKioskText,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  longDate(now),
                  key: const Key('home-date'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: kKioskMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    id: 'holiday',
                    icon: Icons.beach_access_rounded,
                    accent: _kHomeOrange,
                    label: 'Holiday left',
                    value: _holidayLeftLabel,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    id: 'next-leave',
                    icon: Icons.event_rounded,
                    accent: _kHomeTeal,
                    label: 'Next leave',
                    value: _nextLeaveLabel,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    id: 'pending',
                    icon: Icons.hourglass_top_rounded,
                    accent: _kHomeAmber,
                    label: 'Pending requests',
                    value: _leaveLoading ? null : '$_pendingRequestCount',
                  ),
                ),
                if (onFlexi) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      id: 'flexi',
                      icon: Icons.balance_rounded,
                      accent: _kHomePurple,
                      label: 'Flexi balance',
                      value: _flexiSummary?.balance.text,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Expanded(child: _homeGrid(tiles)),
          ],
        ),
      ),
    );
  }

  Widget _homeGrid(List<KioskFeature> tiles) {
    const gap = 16.0;
    final others = tiles.where((f) => f != KioskFeature.requestLeave).toList();
    final topCount = (others.length + 1) ~/ 2;
    final top = others.take(topCount).toList();
    final bottom = others.skip(topCount).toList();

    Widget row(List<KioskFeature> items) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          Expanded(
            child: _HomeTile(
              key: Key('tile-${items[i].name}'),
              info: _homeTileFor(items[i]),
              onTap: () => openFeature(items[i]),
            ),
          ),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tiles.contains(KioskFeature.requestLeave)) ...[
          Expanded(
            child: _PrimaryHomeTile(
              key: const Key('tile-requestLeave'),
              onTap: () => openFeature(KioskFeature.requestLeave),
            ),
          ),
          if (others.isNotEmpty) const SizedBox(width: gap),
        ],
        if (others.isNotEmpty)
          Expanded(
            flex: math.max(2, topCount),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: row(top)),
                if (bottom.isNotEmpty) ...[
                  const SizedBox(height: gap),
                  Expanded(child: row(bottom)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One line of text that shrinks to fit rather than being cut off.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    );
  }
}

/// A white or coloured card that dips slightly while pressed.
class _PressableCard extends StatefulWidget {
  const _PressableCard({
    required this.color,
    required this.onTap,
    required this.child,
    this.border,
  });

  final Color color;
  final Color? border;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 110),
      child: Material(
        color: widget.color,
        elevation: _pressed ? 0 : 1,
        shadowColor: const Color(0x22102F08),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: widget.border == null
              ? BorderSide.none
              : BorderSide(color: widget.border!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (mounted) setState(() => _pressed = value);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _PrimaryHomeTile extends StatelessWidget {
  const _PrimaryHomeTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableCard(
      color: kKioskGreen,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.flight_takeoff_rounded,
                size: 60,
                color: kKioskInk,
              ),
            ),
            const Spacer(),
            const _OneLine(
              'Request Leave',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: kKioskInk,
              ),
            ),
            const SizedBox(height: 6),
            const _OneLine(
              'Book holiday or time off',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: kKioskInk,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: kKioskInk,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Start',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({super.key, required this.info, required this.onTap});

  final _HomeTileInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fact = info.fact;
    return _PressableCard(
      color: Colors.white,
      border: kKioskLine,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: info.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(info.icon, size: 36, color: Colors.white),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 32,
                  color: kKioskMuted,
                ),
              ],
            ),
            const Spacer(),
            _OneLine(
              info.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: kKioskText,
              ),
            ),
            const SizedBox(height: 4),
            _OneLine(
              fact ?? '—',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: fact == null ? kKioskLine : kKioskInk,
              ),
            ),
            if (info.sub != null) ...[
              const SizedBox(height: 2),
              _OneLine(
                info.sub!,
                style: const TextStyle(fontSize: 16, color: kKioskMuted),
              ),
            ],
            if (info.progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: info.progress,
                  minHeight: 8,
                  color: info.accent,
                  backgroundColor: info.accent.withValues(alpha: 0.15),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small at-a-glance figure. A null value is still loading and shows a
/// quiet placeholder.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.id,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  final String id;
  final IconData icon;
  final Color accent;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final shown = value;
    return Container(
      key: Key('stat-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kKioskLine),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 26, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _OneLine(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kKioskMuted,
                  ),
                ),
                const SizedBox(height: 2),
                _OneLine(
                  shown ?? '—',
                  key: Key('stat-$id-value'),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: shown == null ? kKioskLine : kKioskText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
