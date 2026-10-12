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
    final partDayEligibility = _partDayEligibilityForGroup(group);
    final showPartDayRule =
        !partDayEligibility.allowed &&
        partDayEligibility.reason != 'daily_entitlement_mode' &&
        group?.groupRef.trim().toUpperCase() == 'HOL';
    final attachmentRequired = _isAttachmentRequiredForSelection();
    final showAttachment = _attachmentsAllowed || attachmentRequired;
    final busy = _leaveSubmitting;

    Widget formRow(String label, Widget control) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(label, style: kKioskLabel.copyWith(fontSize: 17)),
              ),
            ),
            Expanded(child: control),
          ],
        ),
      );
    }

    return KioskPanel(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 2),
      child: SingleChildScrollView(
        key: const Key('leave-form-scroll'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            formRow(
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
              formRow(
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
            formRow(
              'Dates',
              Row(
                children: [
                  Expanded(
                    child: BigDateButton(
                      key: const Key('leave-date-from'),
                      label: 'From',
                      value: _leaveDateFrom == null
                          ? null
                          : kioskDate(_leaveDateFrom!),
                      onTap: busy
                          ? null
                          : () => _pickLeaveDate(pageContext, from: true),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: BigDateButton(
                      key: const Key('leave-date-to'),
                      label: 'To',
                      value: _leaveDateTo == null
                          ? null
                          : kioskDate(_leaveDateTo!),
                      onTap: busy
                          ? null
                          : () => _pickLeaveDate(pageContext, from: false),
                    ),
                  ),
                ],
              ),
            ),
            formRow(
              'Day part',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KioskChoiceChips<String>(
                    key: const Key('leave-daypart'),
                    options: dayPartOptions,
                    labelOf: _dayPartLabel,
                    selected: selectedDayPart,
                    enabled: !busy,
                    keyOf: (value) => Key('leave-daypart-$value'),
                    onSelected: (value) => _set(() {
                      _selectedDayPart = value;
                      if (value != 'PART') {
                        _leaveTimeFrom = null;
                        _leaveTimeTo = null;
                      }
                      _leaveError = null;
                    }),
                  ),
                  if (showPartDayRule) ...[
                    const SizedBox(height: 8),
                    Text(
                      partDayEligibility.denialMessage,
                      style: const TextStyle(fontSize: 16, color: kKioskMuted),
                    ),
                  ],
                  if (useTimeRange) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: BigDateButton(
                            key: const Key('leave-time-from'),
                            label: 'Start time',
                            placeholder: 'Choose a time',
                            icon: Icons.schedule_rounded,
                            height: 68,
                            value: _leaveTimeFrom == null
                                ? null
                                : _fmtTime(_leaveTimeFrom!),
                            onTap: busy
                                ? null
                                : () => _pickLeaveTime(pageContext, from: true),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: BigDateButton(
                            key: const Key('leave-time-to'),
                            label: 'End time',
                            placeholder: 'Choose a time',
                            icon: Icons.schedule_rounded,
                            height: 68,
                            value: _leaveTimeTo == null
                                ? null
                                : _fmtTime(_leaveTimeTo!),
                            onTap: busy
                                ? null
                                : () =>
                                      _pickLeaveTime(pageContext, from: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            formRow(
              'Notes',
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('leave-notes'),
                      controller: _leaveNotesCtrl,
                      enabled: !busy,
                      minLines: 3,
                      maxLines: 3,
                      style: kKioskBody,
                      decoration: const InputDecoration(
                        hintText: 'Anything your manager should know',
                        hintStyle: TextStyle(fontSize: 18, color: kKioskMuted),
                      ),
                    ),
                  ),
                  if (showAttachment) ...[
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 210,
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
        SizedBox(
          height: 60,
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
        const SizedBox(height: 6),
        if (attachment != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  key: const Key('leave-photo-remove'),
                  tooltip: 'Remove photo',
                  onPressed: busy
                      ? null
                      : () => _set(() => _leaveAttachment = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          )
        else
          Text(
            required
                ? 'A photo is required for this selection.'
                : 'Photo optional (max 10MB).',
            style: TextStyle(
              fontSize: 16,
              color: required ? kKioskAmberText : kKioskMuted,
              fontWeight: required ? FontWeight.w700 : FontWeight.w500,
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
