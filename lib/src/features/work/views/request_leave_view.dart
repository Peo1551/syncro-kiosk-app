part of '../employee_workspace.dart';

/// Request Leave: the form on the left (labels beside the controls so the
/// whole form fits without scrolling), the summary and Send on the right.
extension _RequestLeaveView on EmployeeWorkspaceState {
  Widget _userTab([BuildContext? viewContext]) {
    final pageContext = viewContext ?? context;
    final Widget main;
    if (_leaveLoading) {
      main = const KioskPanel(child: KioskLoading());
    } else if (_leaveGroups.isEmpty) {
      main = KioskPanel(
        child: _leaveError != null
            ? KioskErrorCard(
                message: _leaveError!,
                onRetry: () => unawaited(_refreshLeave()),
              )
            : const KioskEmpty(
                message: 'No leave groups available. Contact your manager.',
                icon: Icons.event_busy_outlined,
              ),
      );
    } else {
      main = _leaveForm(pageContext);
    }
    return KioskSplit(main: main, side: _leaveSummaryPanel());
  }

  Widget _leaveForm(BuildContext pageContext) {
    final group = _selectedLeaveGroup;
    final subtypeOptions = group == null
        ? const <LeaveSubtypeOption>[]
        : _subtypesForGroup(group);
    final showSubtypes =
        group != null &&
        group.allowAlternateSubtypes &&
        subtypeOptions.length > 1;
    final useTimeRange = _usesTimeRangeForSelection(group);
    final dayPartOptions = _dayPartOptionsForGroup(group);
    final selectedDayPart = _selectedDayPartForGroup(group);
    final attachmentRequired = _isAttachmentRequiredForSelection();
    final showAttachment = _attachmentsAllowed || attachmentRequired;
    final busy = _leaveSubmitting;

    Widget section(String label, Widget control) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [KioskLabel(label), control],
        ),
      );
    }

    // Part day is one date with a start and end time, so the To date gives
    // way to the two time buttons and the whole row stays on one line.
    final dateButtons = <Widget>[
      BigDateButton(
        key: const Key('leave-date-from'),
        label: useTimeRange ? 'Date' : 'From',
        value: _leaveDateFrom == null ? null : kioskDate(_leaveDateFrom!),
        onTap: busy ? null : () => _pickLeaveDate(pageContext, from: true),
      ),
      if (!useTimeRange)
        BigDateButton(
          key: const Key('leave-date-to'),
          label: 'To',
          value: _leaveDateTo == null ? null : kioskDate(_leaveDateTo!),
          onTap: busy ? null : () => _pickLeaveDate(pageContext, from: false),
        )
      else ...[
        BigDateButton(
          key: const Key('leave-time-from'),
          label: 'Start time',
          placeholder: 'Choose time',
          icon: Icons.schedule_rounded,
          value: _leaveTimeFrom == null ? null : _fmtTime(_leaveTimeFrom!),
          onTap: busy ? null : () => _pickLeaveTime(pageContext, from: true),
        ),
        BigDateButton(
          key: const Key('leave-time-to'),
          label: 'End time',
          placeholder: 'Choose time',
          icon: Icons.schedule_rounded,
          value: _leaveTimeTo == null ? null : _fmtTime(_leaveTimeTo!),
          onTap: busy ? null : () => _pickLeaveTime(pageContext, from: false),
        ),
      ],
    ];

    return KioskPanel(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: SingleChildScrollView(
        key: const Key('leave-form-scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section(
              'Leave type',
              KioskChoiceChips<String>(
                key: const Key('leave-group'),
                options: [for (final g in _leaveGroups) g.groupId],
                labelOf: (id) =>
                    _leaveGroups.firstWhere((g) => g.groupId == id).name,
                selected: _selectedLeaveGroupId,
                enabled: !busy,
                keyOf: (id) => Key('leave-group-$id'),
                onSelected: (id) => _set(() => _selectLeaveGroup(id)),
              ),
            ),
            if (showSubtypes)
              section(
                'Subtype',
                KioskChoiceChips<int>(
                  key: const Key('leave-subtype'),
                  options: [for (final s in subtypeOptions) s.subtypeId],
                  labelOf: (id) =>
                      subtypeOptions.firstWhere((s) => s.subtypeId == id).name,
                  selected: _selectedLeaveSubtype?.subtypeId,
                  enabled: !busy,
                  keyOf: (id) => Key('leave-subtype-$id'),
                  onSelected: (id) => _set(() {
                    _selectedLeaveSubtypeId = id;
                    _leaveError = null;
                  }),
                ),
              ),
            section(
              'Day part',
              KioskChoiceChips<String>(
                key: const Key('leave-daypart'),
                options: dayPartOptions,
                labelOf: _dayPartLabel,
                selected: selectedDayPart,
                enabled: !busy,
                keyOf: (value) => Key('leave-daypart-$value'),
                onSelected: (value) => _set(() {
                  _selectedDayPart = value;
                  if (value == 'PART') {
                    _leaveDateTo = _leaveDateFrom;
                  } else {
                    _leaveTimeFrom = null;
                    _leaveTimeTo = null;
                  }
                  _leaveError = null;
                }),
              ),
            ),
            section(
              useTimeRange ? 'Date and time' : 'Dates',
              Row(
                children: [
                  for (var i = 0; i < dateButtons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: dateButtons[i]),
                  ],
                ],
              ),
            ),
            section(
              'Notes',
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('leave-notes'),
                      controller: _leaveNotesCtrl,
                      enabled: !busy,
                      minLines: 2,
                      maxLines: 2,
                      style: kKioskBody,
                      decoration: const InputDecoration(
                        hintText: 'Anything your manager should know',
                        hintStyle: TextStyle(fontSize: 18, color: kKioskMuted),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (showAttachment) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 220,
                      child: _attachmentControl(
                        pageContext,
                        required: attachmentRequired,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentControl(
    BuildContext pageContext, {
    required bool required,
  }) {
    final attachment = _leaveAttachment;
    final busy = _leaveSubmitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  key: const Key('leave-photo'),
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await _pickAttachment(pageContext);
                          if (picked == null || !mounted) return;
                          _set(() => _leaveAttachment = picked);
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: BorderSide(
                      color: required && attachment == null
                          ? const Color(0xFFF5C36B)
                          : kKioskLine,
                      width: 2,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 24),
                  label: Text(attachment == null ? 'Take photo' : 'Retake'),
                ),
              ),
            ),
            if (attachment != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                height: 56,
                child: OutlinedButton(
                  key: const Key('leave-photo-remove'),
                  onPressed: busy
                      ? null
                      : () => _set(() => _leaveAttachment = null),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: kKioskLine, width: 2),
                  ),
                  child: const Tooltip(
                    message: 'Remove photo',
                    child: Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          attachment != null
              ? 'Photo added'
              : required
              ? 'Photo required'
              : 'Optional, max 10MB',
          style: TextStyle(
            fontSize: 16,
            color: attachment != null
                ? kKioskPositive
                : required
                ? kKioskAmberText
                : kKioskMuted,
            fontWeight: required || attachment != null
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _leaveSummaryPanel() {
    final group = _selectedLeaveGroup;
    final subtype = _selectedLeaveSubtype;
    final ref = group?.groupRef.trim().toUpperCase() ?? '';
    final dayPart = _selectedDayPartForGroup(group);
    final useTimeRange = _usesTimeRangeForSelection(group);
    final attachmentRequired = _isAttachmentRequiredForSelection();
    final showAttachment = _attachmentsAllowed || attachmentRequired;
    final pendingCount = _leaveRequests.where(_isPendingRequest).length;
    final entitlement = _leaveEntitlement;
    final flexi = FlexiSummary.shouldShow(_flexiSummary) ? _flexiSummary : null;

    String typeText() {
      if (group == null) return '—';
      final sub = subtype?.name.trim() ?? '';
      if (sub.isEmpty || sub.toLowerCase() == group.name.trim().toLowerCase()) {
        return group.name;
      }
      return '${group.name} · $sub';
    }

    String timeText() {
      final from = _leaveTimeFrom;
      final to = _leaveTimeTo;
      if (from == null && to == null) return 'Choose times';
      return '${from == null ? '--:--' : _fmtTime(from)} – '
          '${to == null ? '--:--' : _fmtTime(to)}';
    }

    final lines = <Widget>[
      KioskSummaryLine(label: 'Type', value: typeText()),
      KioskSummaryLine(
        label: 'From',
        value: _leaveDateFrom == null ? '—' : kioskDate(_leaveDateFrom!),
      ),
      KioskSummaryLine(
        label: 'To',
        value: _leaveDateTo == null ? '—' : kioskDate(_leaveDateTo!),
      ),
      KioskSummaryLine(label: 'Day part', value: _dayPartLabel(dayPart)),
      if (useTimeRange) KioskSummaryLine(label: 'Time', value: timeText()),
      if (showAttachment)
        KioskSummaryLine(
          label: 'Photo',
          value: _leaveAttachment != null
              ? 'Added'
              : attachmentRequired
              ? 'Required'
              : 'None',
          valueColor: _leaveAttachment == null && attachmentRequired
              ? kKioskAmberText
              : kKioskText,
        ),
      if (ref == 'HOL' && entitlement != null) ...[
        const Divider(height: 24),
        KioskSummaryLine(
          label: 'Balance now',
          value: entitlement.balanceLabel,
          emphasise: true,
          valueColor: entitlement.balance < 0 ? kKioskNegative : kKioskPositive,
        ),
        KioskSummaryLine(label: 'Booked', value: entitlement.bookedLabel),
      ],
      if (ref == 'FLX' && flexi != null) ...[
        const Divider(height: 24),
        KioskSummaryLine(
          label: 'Flexi balance',
          value: flexi.balance.text,
          emphasise: true,
          valueColor: flexi.balance.isNegative
              ? kKioskNegative
              : kKioskPositive,
        ),
        if (!flexi.projection.futureFlexiLeave.isZero)
          KioskSummaryLine(
            label: 'Already booked',
            value: flexi.projection.futureFlexiLeave.text,
          ),
        KioskSummaryLine(label: 'Lowest allowed', value: flexi.debitLimit.text),
      ],
    ];

    return KioskPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your request', style: kKioskHeading),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...lines,
                  if (pendingCount > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      pendingCount == 1
                          ? '1 request is waiting for a decision. See Request History.'
                          : '$pendingCount requests are waiting for a decision. See Request History.',
                      style: const TextStyle(fontSize: 16, color: kKioskMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_leaveError != null && _leaveGroups.isNotEmpty) ...[
            const SizedBox(height: 12),
            KioskInlineError(_leaveError!),
          ],
          const SizedBox(height: 14),
          KioskPrimaryButton(
            key: const Key('leave-submit'),
            label: 'Send request',
            icon: Icons.send_rounded,
            busy: _leaveSubmitting,
            onPressed: (_leaveLoading || _leaveGroups.isEmpty)
                ? null
                : () => _submitLeaveRequest(context),
          ),
        ],
      ),
    );
  }
}
