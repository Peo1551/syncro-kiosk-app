import 'package:flutter/material.dart';

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

/// Read-only My Flexi screen (project-flexi.md, S10).
class MyFlexiView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final current = summary;
    final theme = Theme.of(context);
    final children = <Widget>[];
    if (current == null || !current.onFlexi) {
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Text(
                    'Your Flexi balance is not available just now. Pull down to try again.',
                    style: theme.textTheme.bodyMedium,
                  ),
          ),
        ),
      );
    } else {
      children.addAll([
        _header(context, current),
        if (current.canRequestFlexiLeave && onRequestFlexiLeave != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: onRequestFlexiLeave,
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Request Flexi leave'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _periodCard(context, current),
        const SizedBox(height: 12),
        _projectionCard(context, current),
        const SizedBox(height: 12),
        _thisPeriodCard(context, current),
        if (current.pastPeriods.isNotEmpty) ...[
          const SizedBox(height: 12),
          _pastPeriodsCard(context, current),
        ],
      ]);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }

  Widget _header(BuildContext context, FlexiSummary s) {
    final theme = Theme.of(context);
    return Container(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current balance',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF52606D),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.balance.text,
                      key: const ValueKey('flexi-balance'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 34,
                        color: s.balance.isNegative
                            ? _negativeColor
                            : _positiveColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.timelapse_rounded,
                  color: Color(0xFF84B01F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Flexi period ${formatFlexiRange(s.period.start, s.period.end)}. '
            '${_daysLeftLabel(s.period.daysLeft)}.',
            style: theme.textTheme.bodySmall,
          ),
          if (s.scheme.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              s.scheme,
              style: theme.textTheme.bodySmall?.copyWith(color: _mutedColor),
            ),
          ],
          if (s.awaitingDecisions > 0) ...[
            const SizedBox(height: 10),
            _Notice(
              text: s.awaitingDecisions == 1
                  ? '1 day is awaiting a manager decision.'
                  : '${s.awaitingDecisions} days are awaiting a manager decision.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _periodCard(BuildContext context, FlexiSummary s) {
    final dayCount = s.days.length;
    return _SectionCard(
      title: 'This Flexi period',
      children: [
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
        _FigureRow(
          label: 'Current balance',
          amount: s.balance,
          emphasise: true,
        ),
        if (s.provisionalDays > 0) ...[
          const SizedBox(height: 8),
          Text(
            s.provisionalDays == 1
                ? '1 day may still change.'
                : '${s.provisionalDays} days may still change.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedColor),
          ),
        ],
      ],
    );
  }

  Widget _projectionCard(BuildContext context, FlexiSummary s) {
    final theme = Theme.of(context);
    final p = s.projection;
    return _SectionCard(
      title: 'End of period',
      children: [
        Text(
          'If you work your expected hours for the rest of the period, '
          'you will carry forward ${p.carriedForward.text}.',
          key: const ValueKey('flexi-projection'),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!p.futureFlexiLeave.isZero) ...[
          const SizedBox(height: 6),
          Text(
            'This allows for Flexi leave already booked: ${p.futureFlexiLeave.text}.',
            style: theme.textTheme.bodySmall?.copyWith(color: _mutedColor),
          ),
        ],
        const SizedBox(height: 10),
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
        const Divider(height: 20),
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
      ],
    );
  }

  Widget _thisPeriodCard(BuildContext context, FlexiSummary s) {
    final theme = Theme.of(context);
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
    return _SectionCard(
      title: 'Day by day',
      children: [
        if (entries.isEmpty)
          Text(
            'Nothing has been counted in this period yet.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            entries[i].day != null
                ? _DayLine(day: entries[i].day!)
                : _LedgerLine(line: entries[i].line!),
          ],
      ],
    );
  }

  Widget _pastPeriodsCard(BuildContext context, FlexiSummary s) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Past periods',
      children: [
        for (var i = 0; i < s.pastPeriods.length; i++) ...[
          if (i > 0) const Divider(height: 20),
          Text(
            formatFlexiRange(s.pastPeriods[i].start, s.pastPeriods[i].end),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _FigureRow(
            label: 'Closing balance',
            amount: s.pastPeriods[i].closing,
          ),
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
      ],
    );
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _amberFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _amberBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF9A3412),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on Request Leave when the Flexi leave group is chosen.
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
