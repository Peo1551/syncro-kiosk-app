part of '../employee_workspace.dart';

/// My Clocking Hub: one week at a time in a table, the week's totals (or the
/// tapped day's rate breakdown) on the right.
extension _ClockingHubView on EmployeeWorkspaceState {
  String get _timesheetWeekLabel {
    final from = _timesheetDateFrom;
    final to = _timesheetDateTo;
    return '${kioskShortDate(from)} – ${kioskDate(to)}';
  }

  Widget _myClockingHubTab([BuildContext? viewContext]) {
    final Widget body;
    if (_timesheetLoading) {
      body = const KioskLoading();
    } else if (_timesheetError != null) {
      body = KioskErrorCard(
        message: _timesheetError!,
        onRetry: () => unawaited(_refreshTimesheets(showLoader: true)),
      );
    } else {
      final rows = _timesheetRows;
      body = KioskTable(
        key: const Key('timesheet-table'),
        columns: const [
          KioskColumn('Day', flex: 4),
          KioskColumn('In', flex: 2),
          KioskColumn('Out', flex: 2),
          KioskColumn('Hours', flex: 2),
          KioskColumn('Status', flex: 3),
        ],
        emptyMessage: _timesheetLoaded
            ? 'No clocking records for this week.'
            : 'Loading your clocking records…',
        selectedRow: _selectedTimesheetIndex,
        onRowTap: (i) => _set(
          () =>
              _selectedTimesheetIndex = _selectedTimesheetIndex == i ? null : i,
        ),
        rowKeys: [
          for (var i = 0; i < rows.length; i++) Key('timesheet-row-$i'),
        ],
        rowColors: [
          for (final e in rows)
            e.isOvertimeDay
                ? const Color(0xFFF1FAF3)
                : e.isUnderTargetDay
                ? const Color(0xFFFFF5F5)
                : null,
        ],
        rows: [for (final e in rows) _timesheetCells(e)],
      );
    }

    final onCurrentWeek = _timesheetOnCurrentWeek;
    final weekBar = Row(
      children: [
        _weekNavButton(
          key: const Key('week-prev'),
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous week',
          onPressed: _timesheetLoading
              ? null
              : () => unawaited(_shiftTimesheetWeek(-1)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(onCurrentWeek ? 'This week' : 'Week', style: kKioskLabel),
              Text(
                _timesheetWeekLabel,
                key: const Key('week-label'),
                textAlign: TextAlign.center,
                style: kKioskHeading,
              ),
            ],
          ),
        ),
        if (!onCurrentWeek) ...[
          SizedBox(
            width: 150,
            child: KioskSecondaryButton(
              key: const Key('week-current'),
              label: 'This week',
              onPressed: _timesheetLoading
                  ? null
                  : () => unawaited(_showCurrentTimesheetWeek()),
            ),
          ),
          const SizedBox(width: 16),
        ],
        _weekNavButton(
          key: const Key('week-next'),
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next week',
          onPressed: _timesheetLoading || onCurrentWeek
              ? null
              : () => unawaited(_shiftTimesheetWeek(1)),
        ),
      ],
    );

    final index = _selectedTimesheetIndex;
    final selected = index != null && index < _timesheetRows.length
        ? _timesheetRows[index]
        : null;

    return KioskSplit(
      main: KioskPanel(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: weekBar,
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ],
          ),
        ),
      ),
      side: selected == null
          ? _timesheetTotalsPanel()
          : _timesheetDayPanel(selected),
    );
  }

  Widget _weekNavButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 72,
      height: 64,
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: kKioskLine, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Tooltip(message: tooltip, child: Icon(icon, size: 36)),
      ),
    );
  }

  String _capitalised(String raw) {
    final text = raw.trim().replaceAll('_', ' ');
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1);
  }

  List<Widget> _timesheetCells(TimesheetEntry e) {
    final date = _parseIsoDate(e.workDate);
    final notes = <String>[
      if (e.shouldShowAbsenceLabelInline) e.absenceLabel!,
      if (e.varianceLabel != null)
        e.isOvertimeDay
            ? 'Over target ${e.varianceLabel}'
            : 'Under target ${e.varianceLabel}',
    ];
    final status = _capitalised(e.status);
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            date == null ? e.dayLabel : kioskShortDate(date),
            style: kKioskBodyStrong,
          ),
          if (notes.isNotEmpty)
            Text(
              notes.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: e.isOvertimeDay
                    ? const Color(0xFF0F766E)
                    : e.isUnderTargetDay
                    ? const Color(0xFFB91C1C)
                    : kKioskMuted,
              ),
            ),
        ],
      ),
      Text(e.clockIn, style: kKioskBody),
      Text(e.clockOut, style: kKioskBody),
      Text(
        e.totalHours,
        style: kKioskBodyStrong.copyWith(
          color: e.hasRateBreakdown ? const Color(0xFF0F766E) : null,
        ),
      ),
      status.isEmpty ? const SizedBox() : StatusChip(status),
    ];
  }

  Widget _timesheetTotalsPanel() {
    final groups = groupTimesheetEntriesByWeek(_timesheetRows);
    TimesheetWeekGroup? week;
    for (final g in groups) {
      if (g.weekStart != null) {
        week = g;
        break;
      }
    }
    final rates = _timesheetRateSummaries();
    final varianceLabel = week != null && week.hasCompleteScheduledTarget
        ? week.varianceMinutes > 0
              ? 'Over'
              : week.varianceMinutes < 0
              ? 'Short'
              : 'Variance'
        : 'Variance';
    return KioskPanel(
      key: const Key('timesheet-totals'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paid hours this week', style: kKioskLabel),
          const SizedBox(height: 6),
          Text(
            week?.payableLabel ?? '00:00',
            key: const Key('timesheet-paid-total'),
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: kKioskText,
            ),
          ),
          const SizedBox(height: 8),
          KioskSummaryLine(
            label: 'Scheduled',
            value: week?.scheduledLabel ?? '--:--',
          ),
          KioskSummaryLine(
            label: varianceLabel,
            value: week?.varianceLabel ?? '--:--',
          ),
          if (rates.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('By rate', style: kKioskLabel),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: ListView(
              children: [
                for (final r in rates)
                  KioskSummaryLine(
                    label: '${r.label}\n${r.useLabel}',
                    value: r.hhmm,
                  ),
              ],
            ),
          ),
          if (_timesheetRows.any((e) => e.hasRateBreakdown))
            const Text(
              'Tap a day to see its rate breakdown.',
              style: TextStyle(fontSize: 16, color: kKioskMuted),
            ),
        ],
      ),
    );
  }

  Widget _timesheetDayPanel(TimesheetEntry entry) {
    final date = _parseIsoDate(entry.workDate);
    return KioskPanel(
      key: const Key('timesheet-day'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            date == null ? entry.dayLabel : kioskDate(date),
            style: kKioskHeading,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                KioskSummaryLine(
                  label: 'Total',
                  value: entry.totalHours,
                  emphasise: true,
                ),
                KioskSummaryLine(
                  label: 'Scheduled',
                  value: entry.hasScheduledTarget
                      ? _minutesToHhmm(entry.scheduledMinutes)
                      : '--:--',
                ),
                KioskSummaryLine(
                  label: entry.isOvertimeDay
                      ? 'Over'
                      : entry.isUnderTargetDay
                      ? 'Short'
                      : 'Variance',
                  value: entry.varianceLabel ?? '00:00',
                ),
                if (entry.rates.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text('Rate breakdown', style: kKioskLabel),
                  for (final rate in entry.rates)
                    KioskSummaryLine(label: rate.label, value: rate.hhmm),
                ],
                if (entry.absenceDetails.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text('Paid leave', style: kKioskLabel),
                  for (final detail in entry.absenceDetails)
                    KioskSummaryLine(
                      label: detail.hasDistinctType
                          ? '${detail.displayLabel}\n${detail.type}'
                          : detail.displayLabel,
                      value: detail.hhmm,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          KioskSecondaryButton(
            key: const Key('timesheet-week-totals'),
            label: 'Week totals',
            icon: Icons.arrow_back_rounded,
            onPressed: () => _set(() => _selectedTimesheetIndex = null),
          ),
        ],
      ),
    );
  }
}
