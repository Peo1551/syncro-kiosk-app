// Building blocks for the signed-in feature screens on a landscape kiosk
// tablet: two panels side by side, big touch targets, nothing to scroll on a
// form. Every feature page uses these so the screens look like one product.
import 'package:flutter/material.dart';

const kKioskInk = Color(0xFF102F08);
const kKioskGreen = Color(0xFF8DC63E);
const kKioskGreenSoft = Color(0xFFEAF5DA);
const kKioskBg = Color(0xFFF5F7FB);
const kKioskText = Color(0xFF1F2937);
const kKioskMuted = Color(0xFF5B6474);
const kKioskLine = Color(0xFFE6E8EE);
const kKioskPositive = Color(0xFF1A9C44);
const kKioskNegative = Color(0xFFDC2626);
const kKioskAmberText = Color(0xFFB45309);

/// Width of the right-hand summary/action panel.
const double kKioskSidePanelWidth = 420;

const TextStyle kKioskLabel = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: kKioskMuted,
);

const TextStyle kKioskBody = TextStyle(fontSize: 18, color: kKioskText);

const TextStyle kKioskBodyStrong = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: kKioskText,
);

const TextStyle kKioskHeading = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w800,
  color: kKioskText,
  height: 1.15,
);

/// Larger type for everything inside a feature page.
ThemeData kioskPageTheme(ThemeData base) {
  final t = base.textTheme;
  return base.copyWith(
    textTheme: t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 18),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 18),
      bodySmall: t.bodySmall?.copyWith(fontSize: 16, color: kKioskMuted),
      titleMedium: t.titleMedium?.copyWith(fontSize: 20),
      titleSmall: t.titleSmall?.copyWith(fontSize: 18),
      labelLarge: t.labelLarge?.copyWith(fontSize: 18),
    ),
  );
}

/// Main content on the left, a fixed-width summary/action panel on the right.
class KioskSplit extends StatelessWidget {
  const KioskSplit({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = kKioskSidePanelWidth,
  });

  final Widget main;
  final Widget side;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: main),
          const SizedBox(width: 20),
          SizedBox(width: sideWidth, child: side),
        ],
      ),
    );
  }
}

/// White card: radius 24, 1px border, no heavy shadow.
class KioskPanel extends StatelessWidget {
  const KioskPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
    this.borderColor = kKioskLine,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

/// Muted section label above a control.
class KioskLabel extends StatelessWidget {
  const KioskLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: kKioskLabel),
  );
}

/// Primary action: full panel width, 76dp tall.
class KioskPrimaryButton extends StatelessWidget {
  const KioskPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 76,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 26),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Secondary action: outlined, 64dp tall.
class KioskSecondaryButton extends StatelessWidget {
  const KioskSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.danger = false,
    this.height = 64,
  });

  final double height;

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? kKioskNegative : kKioskText;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(
            color: danger ? const Color(0xFFFECACA) : kKioskLine,
            width: 2,
          ),
          textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 24),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A row of large selectable chips (56dp tall).
class KioskChoiceChips<T> extends StatelessWidget {
  const KioskChoiceChips({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.keyOf,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final Key Function(T)? keyOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final option in options)
          _KioskChip(
            key: keyOf?.call(option),
            label: labelOf(option),
            selected: option == selected,
            onTap: enabled ? () => onSelected(option) : null,
          ),
      ],
    );
  }
}

class _KioskChip extends StatelessWidget {
  const _KioskChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? kKioskGreenSoft : Colors.white,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: 56,
            constraints: const BoxConstraints(minWidth: 88),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? kKioskGreen : kKioskLine,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 18, color: kKioskInk),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: onTap == null && !selected ? kKioskMuted : kKioskInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "From" / "To" style button showing a chosen value in words.
class BigDateButton extends StatelessWidget {
  const BigDateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Choose date',
    this.icon = Icons.calendar_month_rounded,
    this.height = 68,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String placeholder;

  /// Null leaves the icon out where space is short.
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final hasValue = (value ?? '').isNotEmpty;
    return Material(
      color: Colors.white,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: hasValue ? kKioskGreen : kKioskLine,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 26, color: kKioskInk),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: kKioskLabel.copyWith(fontSize: 15)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hasValue ? value! : placeholder,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: hasValue ? kKioskText : kKioskMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum StatusTone { approved, pending, rejected, cancelled, neutral }

/// Reads a status label the way people do: approved green, pending amber,
/// rejected or declined red, cancelled grey.
StatusTone statusToneOf(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('pending') ||
      lower.contains('await') ||
      lower.contains('requested') ||
      lower.contains('submitted')) {
    return StatusTone.pending;
  }
  if (lower.contains('reject') ||
      lower.contains('declin') ||
      lower.contains('refus')) {
    return StatusTone.rejected;
  }
  if (lower.contains('cancel') ||
      lower.contains('withdrawn') ||
      lower.contains('removed')) {
    return StatusTone.cancelled;
  }
  if (lower.contains('approved') ||
      lower.contains('complete') ||
      lower.contains('booked')) {
    return StatusTone.approved;
  }
  return StatusTone.neutral;
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone});

  final String label;

  /// Defaults to [statusToneOf] the label.
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, Color fg) = switch (tone ??
        statusToneOf(label)) {
      StatusTone.approved => (
        const Color(0xFFEAF8EF),
        const Color(0xFF8FD3A3),
        const Color(0xFF166534),
      ),
      StatusTone.pending => (
        const Color(0xFFFFF7EA),
        const Color(0xFFF5C36B),
        kKioskAmberText,
      ),
      StatusTone.rejected => (
        const Color(0xFFFEF2F2),
        const Color(0xFFFCA5A5),
        const Color(0xFFB91C1C),
      ),
      StatusTone.cancelled => (
        const Color(0xFFF1F3F6),
        const Color(0xFFD0D5DD),
        kKioskMuted,
      ),
      StatusTone.neutral => (
        const Color(0xFFF3F6FA),
        const Color(0xFFD7E0EA),
        kKioskText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// A big figure with its label.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = kKioskText,
    this.caption,
    this.icon,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return KioskPanel(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: kKioskMuted),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(label, style: kKioskLabel)),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: const TextStyle(fontSize: 16, color: kKioskMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One label/value line in a summary panel.
class KioskSummaryLine extends StatelessWidget {
  const KioskSummaryLine({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = kKioskText,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: kKioskLabel.copyWith(fontSize: 17)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: emphasise ? 22 : 18,
                fontWeight: emphasise ? FontWeight.w800 : FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KioskColumn {
  const KioskColumn(this.label, {this.flex = 2, this.align = TextAlign.left});

  final String label;
  final int flex;
  final TextAlign align;
}

/// A table in a card: a header row, then rows that scroll inside the card.
/// Cells are widgets so a cell can hold a chip or two lines of text.
class KioskTable extends StatelessWidget {
  const KioskTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowKeys,
    this.selectedRow,
    this.emptyMessage = 'Nothing to show.',
    this.rowColors,
    this.scrollable = true,
  });

  final List<KioskColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onRowTap;
  final List<Key?>? rowKeys;
  final int? selectedRow;
  final String emptyMessage;
  final List<Color?>? rowColors;

  /// False when the table sits inside something that already scrolls.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kKioskLine)),
      ),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.flex,
              child: Text(c.label, textAlign: c.align, style: kKioskLabel),
            ),
        ],
      ),
    );
    if (rows.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(emptyMessage, style: kKioskBody),
          ),
        ],
      );
    }
    Widget rowAt(int i) {
      final selected = selectedRow == i;
      final cells = rows[i];
      final content = Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? kKioskGreenSoft
              : rowColors?[i] ?? Colors.transparent,
          border: const Border(bottom: BorderSide(color: kKioskLine)),
        ),
        child: Row(
          children: [
            for (var c = 0; c < columns.length; c++)
              Expanded(
                flex: columns[c].flex,
                child: Align(
                  alignment: switch (columns[c].align) {
                    TextAlign.right || TextAlign.end => Alignment.centerRight,
                    TextAlign.center => Alignment.center,
                    _ => Alignment.centerLeft,
                  },
                  child: c < cells.length ? cells[c] : const SizedBox(),
                ),
              ),
          ],
        ),
      );
      final key = rowKeys != null && i < rowKeys!.length ? rowKeys![i] : null;
      if (onRowTap == null) return KeyedSubtree(key: key, child: content);
      return Material(
        key: key,
        color: Colors.transparent,
        child: InkWell(onTap: () => onRowTap!(i), child: content),
      );
    }

    if (!scrollable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, for (var i = 0; i < rows.length; i++) rowAt(i)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            itemBuilder: (_, i) => rowAt(i),
          ),
        ),
      ],
    );
  }
}

/// Centred spinner for a content area that is still loading.
class KioskLoading extends StatelessWidget {
  const KioskLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 56,
      height: 56,
      child: CircularProgressIndicator(strokeWidth: 5),
    ),
  );
}

/// Friendly inline error with a Retry button.
class KioskErrorCard extends StatelessWidget {
  const KioskErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: KioskPanel(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: kKioskMuted),
              const SizedBox(height: 12),
              Text(title, style: kKioskHeading, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: kKioskBody, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  child: KioskSecondaryButton(
                    key: const Key('kiosk-retry'),
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    onPressed: onRetry,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain message in the middle of an empty area.
class KioskEmpty extends StatelessWidget {
  const KioskEmpty({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.inbox_outlined, size: 48, color: kKioskMuted),
            const SizedBox(height: 12),
            Text(message, style: kKioskBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Inline validation or action error inside a panel.
class KioskInlineError extends StatelessWidget {
  const KioskInlineError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: kKioskNegative, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 17,
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber notice line.
class KioskNotice extends StatelessWidget {
  const KioskNotice(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF5C36B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 17,
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = [
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
const _moLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Thu 22 Oct 2026"
String kioskDate(DateTime d) =>
    '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]} ${d.year}';

/// "Thu 22 Oct"
String kioskShortDate(DateTime d) =>
    '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';

/// "October 2026"
String kioskMonth(DateTime d) => '${_moLong[d.month - 1]} ${d.year}';

/// "Thu 22 Oct 2026" for an ISO date, the raw text otherwise.
String kioskIsoDate(String raw) {
  final d = DateTime.tryParse(raw.trim());
  return d == null ? raw : kioskDate(d);
}

/// "Thu 22 Oct – Fri 23 Oct 2026", or one date when both are the same day.
String kioskIsoRange(String from, String to) {
  final a = DateTime.tryParse(from.trim());
  final b = DateTime.tryParse(to.trim());
  if (a == null && b == null) return '--';
  if (a == null) return kioskDate(b!);
  if (b == null || (a.year == b.year && a.month == b.month && a.day == b.day)) {
    return kioskDate(a);
  }
  if (a.year == b.year) return '${kioskShortDate(a)} – ${kioskDate(b)}';
  return '${kioskDate(a)} – ${kioskDate(b)}';
}

/// Opens a date picker drawn larger than standard for a kiosk.
Future<DateTime?> showKioskDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  var initial = initialDate;
  if (initial.isBefore(firstDate)) initial = firstDate;
  if (initial.isAfter(lastDate)) initial = lastDate;
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    initialEntryMode: DatePickerEntryMode.calendarOnly,
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(
        ctx,
      ).copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
  );
}

/// The signed-in screens are laid out for at least [designWidth] x
/// [designHeight] dp. On a tablet whose logical screen is smaller (a 1920x1200
/// panel at density 2.0 is 960x600 dp), the whole area is drawn at that size
/// and scaled down to fit, so the layout and proportions stay the same and
/// nothing wraps or gets cut off. On a large enough screen it does nothing.
class KioskFit extends StatelessWidget {
  const KioskFit({
    super.key,
    required this.child,
    this.designWidth = 1280,
    this.designHeight = 720,
  });

  final Widget child;
  final double designWidth;
  final double designHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedWidth || !box.hasBoundedHeight) return child;
        final scale = [
          1.0,
          box.maxWidth / designWidth,
          box.maxHeight / designHeight,
        ].reduce((a, b) => a < b ? a : b);
        if (scale >= 0.999) return child;
        final size = Size(box.maxWidth / scale, box.maxHeight / scale);
        final media = MediaQuery.of(context);
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: media.copyWith(
                size: size,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: media.viewInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
