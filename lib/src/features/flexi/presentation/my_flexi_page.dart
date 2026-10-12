import 'package:flutter/material.dart';

import '../../../core/widgets/kiosk_ui.dart';
import '../models/flexi_summary.dart';

const Color _positiveColor = Color(0xFF1A9C44);
const Color _negativeColor = Color(0xFFDC2626);
const Color _neutralColor = Color(0xFF0F172A);
const Color _mutedColor = Color(0xFF64748B);
const Color _amberText = Color(0xFFB45309);
const Color _amberFill = Color(0xFFFFF7ED);
const Color _amberBorder = Color(0xFFF5C36B);
const Color _borderColor = Color(0xFFE2E8F0);

Color _amountColor(FlexiAmount amount) {
  if (amount.minutes > 0) return _positiveColor;
  if (amount.minutes < 0) return _negativeColor;
  return _neutralColor;
}

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Thu 9 Oct" (or "Thu 9 Oct 2026" with [withYear]). Falls back to the raw
/// text when the server sends something that is not a plain date.
String formatFlexiDate(String raw, {bool withYear = false}) {
  final date = DateTime.tryParse(raw.trim());
  if (date == null) return raw;
  final base =
      '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';
  return withYear ? '$base ${date.year}' : base;
}

String formatFlexiRange(String start, String end) {
  return '${formatFlexiDate(start, withYear: true)} to '
      '${formatFlexiDate(end, withYear: true)}';
}

String _daysLeftLabel(int days) {
  if (days <= 0) return 'Last day of the period';
  return days == 1 ? '1 day left' : '$days days left';
}

/// The My Flexi tile on the My Work tab. Renders nothing unless the server says
/// the employee is on Flexi, so a failed or "not on Flexi" answer leaves the
/// menu exactly as it was.
class MyFlexiMenuTile extends StatelessWidget {
  const MyFlexiMenuTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final FlexiSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = summary;
    if (current == null || !FlexiSummary.shouldShow(current)) {
      return const SizedBox.shrink();
    }
    final awaiting = current.awaitingDecisions;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          leading: const Icon(
            Icons.timelapse_outlined,
            color: Color(0xFF1E2433),
          ),
          title: Text(
            'My Flexi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            'Current balance: ${current.balance.text}. '
            '${_daysLeftLabel(current.period.daysLeft)} in this period.',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (awaiting > 0) ...[
                _Pill(
                  label: awaiting == 1 ? '1 awaiting' : '$awaiting awaiting',
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Read-only My Flexi screen (project-flexi.md, S10), laid out for a
/// landscape kiosk: the balance on a dark card on the left, the period's
/// figures in a table on the right.
class MyFlexiView extends StatefulWidget {
  const MyFlexiView({
    super.key,
    required this.summary,
    required this.loading,
    required this.onRefresh,
    this.onRequestFlexiLeave,
  });

  final FlexiSummary? summary;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRequestFlexiLeave;

  @override
  State<MyFlexiView> createState() => _MyFlexiViewState();
}

enum _FlexiSection { period, days, past }

class _MyFlexiViewState extends State<MyFlexiView> {
  _FlexiSection _section = _FlexiSection.period;

  @override
  Widget build(BuildContext context) {
    final current = widget.summary;
    if (current == null || !current.onFlexi) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: widget.loading
            ? const KioskLoading()
            : KioskErrorCard(
                title: 'Flexi balance unavailable',
                message: 'Your Flexi balance is not available just now.',
                onRetry: () => widget.onRefresh(),
              ),
      );
    }
    final sections = [
      _FlexiSection.period,
      _FlexiSection.days,
      if (current.pastPeriods.isNotEmpty) _FlexiSection.past,
    ];
    final section = sections.contains(_section)
        ? _section
        : _FlexiSection.period;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: kKioskSidePanelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _balanceCard(current)),
                if (current.canRequestFlexiLeave &&
                    widget.onRequestFlexiLeave != null) ...[
                  const SizedBox(height: 16),
                  KioskPrimaryButton(
                    key: const Key('flexi-request-leave'),
                    label: 'Request Flexi leave',
                    icon: Icons.event_available_rounded,
                    onPressed: widget.onRequestFlexiLeave,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: KioskPanel(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                      child: KioskChoiceChips<_FlexiSection>(
                        options: sections,
                        selected: section,
                        keyOf: (s) => Key('flexi-section-${s.name}'),
                        labelOf: (s) => switch (s) {
                          _FlexiSection.period => 'This period',
                          _FlexiSection.days => 'Day by day',
                          _FlexiSection.past => 'Past periods',
                        },
                        onSelected: (s) => setState(() => _section = s),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: widget.onRefresh,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: switch (section) {
                            _FlexiSection.period => _periodRows(current),
                            _FlexiSection.days => _dayRows(current),
                            _FlexiSection.past => _pastRows(current),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(FlexiSummary s) {
    const soft = Color(0xFFC9D6C2);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: kKioskInk,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timelapse_rounded, color: kKioskGreen, size: 28),
              SizedBox(width: 10),
              Text(
                'Current balance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: soft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              s.balance.text,
              key: const ValueKey('flexi-balance'),
              style: TextStyle(
                fontSize: 72,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: s.balance.isNegative
                    ? const Color(0xFFFCA5A5)
                    : kKioskGreen,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Flexi period ${formatFlexiRange(s.period.start, s.period.end)}',
            style: const TextStyle(fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _daysLeftLabel(s.period.daysLeft),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (s.scheme.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(s.scheme, style: const TextStyle(fontSize: 16, color: soft)),
          ],
          const Spacer(),
          if (s.awaitingDecisions > 0) ...[
            _Pill(
              label: s.awaitingDecisions == 1
                  ? '1 day is awaiting a manager decision'
                  : '${s.awaitingDecisions} days are awaiting a manager decision',
            ),
            const SizedBox(height: 14),
          ],
          Text(
            'If you work your expected hours for the rest of the period, '
            'you will carry forward ${s.projection.carriedForward.text}.',
            key: const ValueKey('flexi-projection'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (!s.projection.futureFlexiLeave.isZero) ...[
            const SizedBox(height: 6),
            Text(
              'This allows for Flexi leave already booked: '
              '${s.projection.futureFlexiLeave.text}.',
              style: const TextStyle(fontSize: 16, color: soft),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(text, style: kKioskLabel.copyWith(fontSize: 17)),
  );

  List<Widget> _periodRows(FlexiSummary s) {
    final dayCount = s.days.length;
    final p = s.projection;
    return [
      _heading('This Flexi period'),
      _FigureRow(
        label: s.broughtForwardProvisional
            ? 'Brought forward (provisional)'
            : 'Brought forward',
        detail: s.broughtForwardProvisional
            ? 'The last period has not been settled yet.'
            : null,
        amount: s.broughtForward,
      ),
      _FigureRow(
        label: 'Earned this period',
        detail: dayCount == 0
            ? null
            : dayCount == 1
            ? 'From 1 day'
            : 'From $dayCount days',
        amount: s.earned,
      ),
      _FigureRow(
        label: 'Flexi leave used',
        amount: s.flexiLeave,
        colorOverride: s.flexiLeave.isZero ? null : _neutralColor,
      ),
      _FigureRow(label: 'Adjustments', amount: s.adjustments),
      const Divider(height: 20),
      _FigureRow(label: 'Current balance', amount: s.balance, emphasise: true),
      if (s.provisionalDays > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            s.provisionalDays == 1
                ? '1 day may still change.'
                : '${s.provisionalDays} days may still change.',
            style: const TextStyle(fontSize: 16, color: kKioskMuted),
          ),
        ),
      const Divider(height: 28),
      _heading('End of period'),
      _FigureRow(label: 'Projected carry forward', amount: p.carriedForward),
      _FigureRow(
        label: 'Projected forfeited hours',
        amount: p.forfeited,
        colorOverride: p.forfeited.isZero ? _neutralColor : _amberText,
        highlight: !p.forfeited.isZero,
      ),
      _FigureRow(
        label: 'Projected Flexi deduction',
        amount: p.deduction,
        colorOverride: p.deduction.isZero ? _neutralColor : _amberText,
        highlight: !p.deduction.isZero,
      ),
      _FigureRow(
        label: 'Credit limit',
        detail: 'The most you can carry forward',
        amount: s.creditLimit,
        colorOverride: _neutralColor,
      ),
      _FigureRow(
        label: 'Debit limit',
        detail: 'The most you can be behind',
        amount: s.debitLimit,
        colorOverride: _neutralColor,
      ),
    ];
  }

  List<Widget> _dayRows(FlexiSummary s) {
    // Newest first; on each date the day comes before any ledger line.
    final entries = <_TimelineEntry>[
      for (final day in s.days) _TimelineEntry(date: day.date, day: day),
      for (final line in s.ledger) _TimelineEntry(date: line.date, line: line),
    ];
    entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return (a.day != null ? 0 : 1).compareTo(b.day != null ? 0 : 1);
    });
    if (entries.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Nothing has been counted in this period yet.',
            style: kKioskBody,
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < entries.length; i++) ...[
        if (i > 0) const Divider(height: 24),
        if (i == 0) const SizedBox(height: 8),
        entries[i].day != null
            ? _DayLine(day: entries[i].day!)
            : _LedgerLine(line: entries[i].line!),
      ],
    ];
  }

  List<Widget> _pastRows(FlexiSummary s) {
    return [
      for (var i = 0; i < s.pastPeriods.length; i++) ...[
        if (i > 0) const Divider(height: 24),
        _heading(
          formatFlexiRange(s.pastPeriods[i].start, s.pastPeriods[i].end),
        ),
        _FigureRow(label: 'Closing balance', amount: s.pastPeriods[i].closing),
        _FigureRow(
          label: 'Carried forward',
          amount: s.pastPeriods[i].carriedForward,
        ),
        if (!s.pastPeriods[i].forfeited.isZero)
          _FigureRow(
            label: s.pastPeriods[i].forfeitedPaid
                ? 'Paid instead of carried'
                : 'Forfeited',
            amount: s.pastPeriods[i].forfeited,
            colorOverride: s.pastPeriods[i].forfeitedPaid
                ? _neutralColor
                : _amberText,
          ),
        if (!s.pastPeriods[i].deduction.isZero)
          _FigureRow(
            label: 'Flexi deduction',
            amount: s.pastPeriods[i].deduction,
            colorOverride: _amberText,
          ),
      ],
    ];
  }
}

class _TimelineEntry {
  const _TimelineEntry({required this.date, this.day, this.line});

  final String date;
  final FlexiDay? day;
  final FlexiLedgerLine? line;
}

class _DayLine extends StatelessWidget {
  const _DayLine({required this.day});

  final FlexiDay day;

  String? get _noShowLabel {
    switch (day.noShow) {
      case FlexiNoShow.awaiting:
        return 'Awaiting manager decision';
      case FlexiNoShow.balance:
        return 'Taken from Flexi balance';
      case FlexiNoShow.unpaid:
        return 'Unpaid';
      case FlexiNoShow.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final noShow = _noShowLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    formatFlexiDate(day.date),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (day.provisional) const _Pill(label: 'May change'),
                ],
              ),
            ),
            Text(
              day.movement.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _amountColor(day.movement),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Expected ${day.expected.text} · Counted ${day.counted.text}',
          style: small?.copyWith(color: _mutedColor),
        ),
        if (noShow != null) ...[
          const SizedBox(height: 4),
          Text(
            'No attendance: $noShow',
            style: small?.copyWith(
              color: day.noShow == FlexiNoShow.awaiting
                  ? _amberText
                  : _neutralColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (!day.flexiLeave.isZero) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Flexi leave',
                  style: small?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                day.flexiLeave.text,
                style: small?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine({required this.line});

  final FlexiLedgerLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final related = line.relatedDate;
    final detail = <String>[
      if (related != null && related != line.date)
        'For ${formatFlexiDate(related)}',
      if (line.reason.isNotEmpty) line.reason,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${formatFlexiDate(line.date)} · ${line.label}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              line.amount.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _amountColor(line.amount),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(color: _mutedColor),
          ),
        ],
      ],
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.label,
    required this.amount,
    this.detail,
    this.colorOverride,
    this.emphasise = false,
    this.highlight = false,
  });

  final String label;
  final String? detail;
  final FlexiAmount amount;
  final Color? colorOverride;
  final bool emphasise;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle =
        (emphasise ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(
              color: colorOverride ?? _amountColor(amount),
              fontWeight: FontWeight.w700,
            );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    (emphasise
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                          fontWeight: emphasise
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _mutedColor,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(amount.text, style: valueStyle),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: highlight
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _amberFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _amberBorder),
              ),
              child: row,
            )
          : row,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _amberFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _amberBorder),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _amberText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class FlexiRequestBalanceNote extends StatelessWidget {
  const FlexiRequestBalanceNote({super.key, required this.summary});

  final FlexiSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booked = summary.projection.futureFlexiLeave;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your Flexi balance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                summary.balance.text,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: summary.balance.isNegative
                      ? _negativeColor
                      : _positiveColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (!booked.isZero) ...[
            const SizedBox(height: 4),
            Text(
              'Flexi leave already booked for the rest of this period: ${booked.text}.',
              style: theme.textTheme.bodySmall?.copyWith(color: _mutedColor),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'You can go down to ${summary.debitLimit.text}.',
            style: theme.textTheme.bodySmall?.copyWith(color: _mutedColor),
          ),
        ],
      ),
    );
  }
}
