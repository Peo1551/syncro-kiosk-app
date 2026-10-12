part of '../employee_workspace.dart';

/// Request History and Upcoming Leave: a list on the left, the chosen row's
/// details (and its Cancel / Request removal actions) on the right.
extension _LeaveListsView on EmployeeWorkspaceState {
  // ------------------------------------------------------------ shared bits

  bool _inHistoryFilter(LeaveRequest request, _HistoryFilter filter) {
    switch (filter) {
      case _HistoryFilter.pending:
        return _isPendingRequest(request);
      case _HistoryFilter.approved:
        return _isApprovedRequest(request);
      case _HistoryFilter.rejected:
        return _isRejectedRequest(request);
      case _HistoryFilter.all:
        return _isPendingRequest(request) ||
            _isApprovedRequest(request) ||
            _isRejectedRequest(request);
    }
  }

  String _historyFilterLabel(_HistoryFilter filter) {
    switch (filter) {
      case _HistoryFilter.all:
        return 'All';
      case _HistoryFilter.pending:
        return 'Pending';
      case _HistoryFilter.approved:
        return 'Approved';
      case _HistoryFilter.rejected:
        return 'Rejected';
    }
  }

  /// As the employee app: pending rows show the live status, decided rows
  /// the history wording.
  String _historyStatusFor(LeaveRequest request) => _isPendingRequest(request)
      ? request.activeStatusLabel
      : request.historyStatusLabel;

  StatusTone _requestTone(LeaveRequest request, String label) {
    if (!request.hasRemovalDecision &&
        request.normalizedStatus.contains('cancel')) {
      return StatusTone.cancelled;
    }
    return statusToneOf(label);
  }

  /// The length the server recorded for the request.
  String _requestLengthText(LeaveRequest request) {
    if ((request.timeRangeText ?? '').isNotEmpty && request.minutes > 0) {
      final h = request.minutes ~/ 60;
      final m = request.minutes % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    if (request.days > 0) {
      final text = request.days == request.days.roundToDouble()
          ? request.days.toStringAsFixed(0)
          : request.days
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), '');
      return request.days == 1 ? '1 day' : '$text days';
    }
    return request.dayPartLabel;
  }

  String _requestTypeText(LeaveRequest request) {
    final group = request.groupName.trim();
    final sub = request.subtypeName.trim();
    if (sub.isEmpty || sub.toLowerCase() == group.toLowerCase()) {
      return group.isEmpty ? 'Leave' : group;
    }
    return group.isEmpty ? sub : '$group · $sub';
  }

  Widget _listRow({
    Key? key,
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    required String length,
    required Widget chip,
  }) {
    return Material(
      key: key,
      color: selected ? kKioskGreenSoft : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? kKioskGreen : Colors.transparent,
                width: 5,
              ),
              bottom: const BorderSide(color: kKioskLine),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: kKioskText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, color: kKioskMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  length,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kKioskBodyStrong,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 3,
                child: Align(alignment: Alignment.centerRight, child: chip),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: kKioskMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthHeader(String text) => Container(
    color: kKioskBg,
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
    child: Text(text, style: kKioskLabel.copyWith(fontSize: 17)),
  );

  Widget _listCard({Widget? top, required Widget body}) {
    return KioskPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (top != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: top,
              ),
              const Divider(height: 1),
            ],
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// Details of one of the employee's own requests, with the actions the
  /// server allows for it.
  Widget _requestDetailPanel(
    BuildContext viewContext,
    LeaveRequest? request, {
    required String Function(LeaveRequest) statusOf,
    required String emptyMessage,
  }) {
    if (request == null) {
      return KioskPanel(
        child: KioskEmpty(
          message: emptyMessage,
          icon: Icons.touch_app_outlined,
        ),
      );
    }
    final actionBusy = _leaveActionRequestId == request.requestId;
    final showActions = !request.isHistoryRejected;
    final showCancelAction =
        showActions && request.canCancel && !request.hasPendingRemovalWorkflow;
    final showRemovalAction =
        showActions &&
        request.canRequestRemoval &&
        !request.hasPendingRemovalWorkflow;
    final status = statusOf(request);
    final notes = request.notes.trim();
    return KioskPanel(
      key: Key('request-detail-${request.requestId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(status, tone: _requestTone(request, status)),
          ),
          const SizedBox(height: 12),
          Text(
            kioskIsoRange(request.dateFrom, request.dateTo),
            style: kKioskHeading,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KioskSummaryLine(
                    label: 'Type',
                    value: request.groupName.trim().isEmpty
                        ? '—'
                        : request.groupName,
                  ),
                  KioskSummaryLine(
                    label: 'Subtype',
                    value: request.subtypeName.trim().isEmpty
                        ? '—'
                        : request.subtypeName,
                  ),
                  KioskSummaryLine(
                    label: 'Day part',
                    value: request.dayPartLabel,
                  ),
                  if ((request.timeRangeText ?? '').isNotEmpty)
                    KioskSummaryLine(
                      label: 'Time',
                      value: request.timeRangeText!,
                    ),
                  KioskSummaryLine(
                    label: 'Length',
                    value: _requestLengthText(request),
                  ),
                  if (request.hasAttachment)
                    const KioskSummaryLine(label: 'Photo', value: 'Included'),
                  if ((request.removalStatusText ?? '').isNotEmpty)
                    KioskSummaryLine(
                      label: 'Removal',
                      value: request.removalStatusText!,
                    ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Notes', style: kKioskLabel),
                    const SizedBox(height: 4),
                    Text(notes, style: kKioskBody),
                  ],
                ],
              ),
            ),
          ),
          if (showCancelAction) ...[
            const SizedBox(height: 12),
            KioskSecondaryButton(
              key: const Key('request-cancel'),
              label: 'Cancel request',
              icon: Icons.close_rounded,
              danger: true,
              busy: actionBusy,
              onPressed: () => _cancelLeaveRequest(viewContext, request),
            ),
          ],
          if (showRemovalAction) ...[
            const SizedBox(height: 12),
            KioskSecondaryButton(
              key: const Key('request-removal'),
              label: 'Request removal',
              icon: Icons.assignment_late_outlined,
              onPressed: actionBusy
                  ? null
                  : () => _requestLeaveRemoval(viewContext, request),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------- Request History

  Widget _requestHistoryTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final requested = _leaveRequests.where((r) => r.isRequested).toList();
    final rows = requested
        .where((r) => _inHistoryFilter(r, _historyFilter))
        .toList();
    LeaveRequest? selected;
    for (final r in rows) {
      if (r.requestId == _selectedHistoryRequestId) selected = r;
    }
    int countFor(_HistoryFilter f) =>
        requested.where((r) => _inHistoryFilter(r, f)).length;

    final Widget body;
    if (_leaveLoading) {
      body = const KioskLoading();
    } else if (_leaveError != null && _leaveRequests.isEmpty) {
      body = KioskErrorCard(
        message: _leaveError!,
        onRetry: () => unawaited(_refreshLeave()),
      );
    } else if (rows.isEmpty) {
      body = KioskEmpty(
        message: _historyFilter == _HistoryFilter.all
            ? 'No requests yet.'
            : 'No ${_historyFilterLabel(_historyFilter).toLowerCase()} requests yet.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refreshLeave,
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            final status = _historyStatusFor(r);
            return _listRow(
              key: Key('history-row-${r.requestId}'),
              selected: r.requestId == _selectedHistoryRequestId,
              onTap: () => _set(() => _selectedHistoryRequestId = r.requestId),
              title: kioskIsoRange(r.dateFrom, r.dateTo),
              subtitle: _requestTypeText(r),
              length: _requestLengthText(r),
              chip: StatusChip(status, tone: _requestTone(r, status)),
            );
          },
        ),
      );
    }

    return KioskSplit(
      main: _listCard(
        top: KioskChoiceChips<_HistoryFilter>(
          options: _HistoryFilter.values,
          labelOf: (f) {
            final n = countFor(f);
            return n == 0
                ? _historyFilterLabel(f)
                : '${_historyFilterLabel(f)} ($n)';
          },
          selected: _historyFilter,
          keyOf: (f) => Key('history-filter-${f.name}'),
          onSelected: (f) => _set(() => _historyFilter = f),
        ),
        body: body,
      ),
      side: _requestDetailPanel(
        pageContext,
        selected,
        statusOf: _historyStatusFor,
        emptyMessage: 'Tap a request to see its details.',
      ),
    );
  }

  // ----------------------------------------------------------- Upcoming Leave

  Widget _upcomingTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final views = _upcomingLeaveViews;
    final tabs = <int>[
      0,
      if (views?.canViewTeam == true) 1,
      if (views?.canViewCompany == true) 2,
    ];
    final current = tabs.contains(_upcomingView) ? _upcomingView : 0;
    const tabLabels = ['My leave', 'My team', 'Company'];

    final Widget body;
    final Widget side;
    if (current == 0) {
      final rows = _upcomingLeaveRows();
      final index = _selectedUpcomingIndex;
      final selected = index != null && index < rows.length
          ? rows[index]
          : null;
      body = _leaveLoading
          ? const KioskLoading()
          : rows.isEmpty
          ? const KioskEmpty(
              message: 'No upcoming leave booked in the next 12 months.',
              icon: Icons.event_available_outlined,
            )
          : _groupedByMonth(
              starts: [for (final r in rows) r.dateFrom],
              rowAt: (i) {
                final r = rows[i];
                return _listRow(
                  key: Key('upcoming-row-$i'),
                  selected: i == index,
                  onTap: () => _set(() => _selectedUpcomingIndex = i),
                  title: kioskIsoRange(r.dateFrom, r.dateTo),
                  subtitle: _requestTypeText(r),
                  length: _requestLengthText(r),
                  chip: StatusChip(
                    r.activeStatusLabel,
                    tone: _requestTone(r, r.activeStatusLabel),
                  ),
                );
              },
            );
      side = selected == null
          ? _upcomingSummaryPanel(rows.length)
          : _requestDetailPanel(
              pageContext,
              selected,
              statusOf: (r) => r.activeStatusLabel,
              emptyMessage: '',
            );
    } else {
      final rows = _filterSharedUpcomingRows(
        current == 1
            ? (views?.team ?? const <LeaveUpcomingEntry>[])
            : (views?.company ?? const <LeaveUpcomingEntry>[]),
      );
      final index = _selectedUpcomingIndex;
      final selected = index != null && index < rows.length
          ? rows[index]
          : null;
      final error = (_upcomingLeaveError ?? '').trim();
      final Widget list;
      if (_upcomingLeaveLoading && views == null) {
        list = const KioskLoading();
      } else if (rows.isEmpty) {
        list = KioskEmpty(
          message: current == 1
              ? 'No upcoming leave is booked for your team in the next 12 months.'
              : 'No upcoming leave is booked across the company in the next 12 months.',
          icon: Icons.groups_outlined,
        );
      } else {
        list = _groupedByMonth(
          starts: [for (final e in rows) e.dateFrom],
          rowAt: (i) {
            final e = rows[i];
            return _listRow(
              key: Key('upcoming-row-$i'),
              selected: i == index,
              onTap: () => _set(() => _selectedUpcomingIndex = i),
              title: kioskIsoRange(e.dateFrom, e.dateTo),
              subtitle: '${e.typeLabel} · ${_peopleNames(e)}',
              length: e.dayPartLabel,
              chip: StatusChip(
                e.count == 1 ? '1 person' : '${e.count} people',
                tone: StatusTone.neutral,
              ),
            );
          },
        );
      }
      body = error.isEmpty
          ? list
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: KioskNotice(error),
                ),
                Expanded(child: list),
              ],
            );
      side = selected == null
          ? _upcomingSummaryPanel(rows.length)
          : _sharedUpcomingDetailPanel(selected);
    }

    return KioskSplit(
      main: _listCard(
        top: tabs.length > 1
            ? KioskChoiceChips<int>(
                options: tabs,
                labelOf: (i) => tabLabels[i],
                selected: current,
                keyOf: (i) => Key('upcoming-tab-$i'),
                onSelected: (i) => _set(() {
                  _upcomingView = i;
                  _selectedUpcomingIndex = null;
                }),
              )
            : null,
        body: body,
      ),
      side: side,
    );
  }

  /// Rows under month headings ("October 2026"), in the order given.
  Widget _groupedByMonth({
    required List<String> starts,
    required Widget Function(int index) rowAt,
  }) {
    final items = <Widget>[];
    String? lastMonth;
    for (var i = 0; i < starts.length; i++) {
      final date = _parseIsoDate(starts[i]);
      final month = date == null ? 'Other dates' : kioskMonth(date);
      if (month != lastMonth) {
        items.add(_monthHeader(month));
        lastMonth = month;
      }
      items.add(rowAt(i));
    }
    return RefreshIndicator(
      onRefresh: _refreshLeave,
      child: ListView(children: items),
    );
  }

  String _peopleNames(LeaveUpcomingEntry entry) {
    final names = [
      for (final p in entry.people)
        p.name.trim().isEmpty ? 'Employee' : p.name.trim(),
    ];
    return names.isEmpty ? '—' : names.join(', ');
  }

  Widget _upcomingSummaryPanel(int count) {
    return KioskPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Next 12 months', style: kKioskLabel),
          const SizedBox(height: 8),
          Text(
            count == 1 ? '1 booking' : '$count bookings',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: kKioskText,
            ),
          ),
          if (count > 0) ...[
            const Spacer(),
            const KioskEmpty(
              message: 'Tap a booking to see its details.',
              icon: Icons.touch_app_outlined,
            ),
            const Spacer(),
          ],
        ],
      ),
    );
  }

  Widget _sharedUpcomingDetailPanel(LeaveUpcomingEntry entry) {
    return KioskPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kioskIsoRange(entry.dateFrom, entry.dateTo),
            style: kKioskHeading,
          ),
          const SizedBox(height: 8),
          KioskSummaryLine(label: 'Type', value: entry.typeLabel),
          KioskSummaryLine(label: 'Day part', value: entry.dayPartLabel),
          const Divider(height: 24),
          Text(
            entry.count == 1 ? '1 person' : '${entry.count} people',
            style: kKioskLabel,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              children: [
                for (final person in entry.people)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name.trim().isEmpty ? 'Employee' : person.name,
                          style: kKioskBodyStrong,
                        ),
                        if ([
                          person.departmentName.trim(),
                          person.siteName.trim(),
                        ].any((s) => s.isNotEmpty))
                          Text(
                            [
                              person.departmentName.trim(),
                              person.siteName.trim(),
                            ].where((s) => s.isNotEmpty).join(' • '),
                            style: const TextStyle(
                              fontSize: 16,
                              color: kKioskMuted,
                            ),
                          ),
                      ],
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
