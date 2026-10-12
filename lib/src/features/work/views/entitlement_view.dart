part of '../employee_workspace.dart';

/// My Entitlement: the figures the holiday summary returns as big cards, the
/// detail in a table underneath.
extension _EntitlementView on EmployeeWorkspaceState {
  Widget _myEntitlementTab([BuildContext? viewContext]) {
    final entitlement = _leaveEntitlement;
    final Widget content;
    if (_entitlementLoading) {
      content = const KioskLoading();
    } else if (entitlement == null && _entitlementError != null) {
      content = KioskErrorCard(
        message: _entitlementError!,
        onRetry: () => unawaited(_refreshEntitlement()),
      );
    } else if (entitlement == null) {
      content = const KioskEmpty(message: 'No entitlement data available.');
    } else {
      content = _entitlementContent(entitlement);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: content,
    );
  }

  Widget _entitlementContent(LeaveEntitlement e) {
    final balanceColor = e.balance < 0 ? kKioskNegative : kKioskPositive;
    final basis = e.isFallback
        ? 'Estimated from approved holiday already visible'
        : e.needsSetup
        ? 'Default allowance while setup completes'
        : 'Live balance';
    final year = e.yearStart.trim().isEmpty && e.yearEnd.trim().isEmpty
        ? '—'
        : '${kioskIsoDate(e.yearStart)} to ${kioskIsoDate(e.yearEnd)}';
    final percent = (e.progressValue * 100).round();

    Widget tableRow(String label, String value, {Color? color}) {
      return Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kKioskLine)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: kKioskLabel.copyWith(fontSize: 17)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: kKioskBodyStrong.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (e.isFallback) ...[
          const KioskNotice(
            'Showing a default entitlement estimate while the live summary service is unavailable.',
          ),
          const SizedBox(height: 16),
        ] else if (_entitlementError != null) ...[
          KioskInlineError('Latest refresh failed: $_entitlementError'),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: StatCard(
                key: const Key('stat-allowance'),
                label: 'Allowance',
                value: e.totalLabel,
                icon: Icons.event_note_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                key: const Key('stat-booked'),
                label: 'Booked',
                value: e.bookedLabel,
                valueColor: kKioskAmberText,
                icon: Icons.event_busy_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                key: const Key('stat-remaining'),
                label: 'Remaining',
                value: e.balanceLabel,
                valueColor: balanceColor,
                icon: Icons.beach_access_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: KioskPanel(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Scrollbar(
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Breakdown', style: kKioskHeading),
                          ),
                          Text('$percent% used', style: kKioskLabel),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 16,
                          value: e.progressValue,
                          backgroundColor: const Color(0xFFE2E8F0),
                          color: kKioskGreen,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    tableRow('Leave year', year),
                    tableRow('Measured in', e.isHours ? 'Hours' : 'Days'),
                    tableRow('Allowance', e.totalLabel),
                    tableRow('Booked', e.bookedLabel),
                    tableRow('Remaining', e.balanceLabel, color: balanceColor),
                    tableRow('Figures', basis),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
