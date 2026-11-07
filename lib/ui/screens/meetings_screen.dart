import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels_screen.dart';

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final open = st.openMeeting;
    final past = st.meetings.where((m) => m.s('status') == 'closed').toList();
    final attendance = open?.l('attendance') ?? const <Json>[];
    final present = attendance.where((a) => a.b('present')).length;
    final total = attendance.length;
    final quorum = st.org!.i('meeting_quorum_pct');
    final hasQuorum = total > 0 && present * 100 >= quorum * total;

    return AppPageView(
      children: [
        SaccoCard(
          color: open != null ? cs.primaryContainer : cs.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          open != null ? 'Meeting #${open.i('meeting_number')} is Open' : 'No Active Meeting',
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: open != null ? cs.onPrimaryContainer : null),
                        ),
                        Text(open != null ? Dates.day(open['meeting_date']) : 'Open a meeting to record cash with quorum.', style: tt.bodySmall),
                      ],
                    ),
                  ),
                  Pill(text: open != null ? 'OPEN' : 'IDLE', color: open != null ? okGreen : Colors.grey),
                ],
              ),
              if (st.role.canRunMeetings) ...[
                gap,
                if (open == null)
                  FilledButton.icon(onPressed: () => _cashCount(context, st), icon: const Icon(Icons.play_arrow), label: Text(st.t('Open Weekly Meeting')))
                else
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    onPressed: () => _cashCount(context, st, closing: open),
                    icon: const Icon(Icons.stop),
                    label: Text(st.t('Close Meeting (Reconcile Cash)')),
                  ),
              ],
            ],
          ),
        ),
        if (open != null) ...[
          SaccoCard(
            elevation: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('Attendance & Quorum', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Pill(
                      text: hasQuorum ? st.t('Quorum Reached') : 'Need $quorum%: $present/$total',
                      color: hasQuorum ? okGreenBg : warnOrange,
                      foreground: hasQuorum ? okGreen : Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Opening cash ${money(context, open.i('opening_cash'))} counted by 2 people. Ledger said ${money(context, open.i('ledger_cash_at_open'))}.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (open.i('opening_cash') != open.i('ledger_cash_at_open'))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Count differs from the ledger. Find out why before closing.',
                      style: tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
                    ),
                  ),
                gap,
                for (final a in attendance)
                  InkWell(
                    onTap: st.role.canRunMeetings ? () => runAndTell(context, () => st.api.setAttendance(open.s('id'), a.s('member_id'), !a.b('present'))) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(a.b('present') ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: a.b('present') ? okGreen : cs.outline),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.s('name'), style: tt.bodyMedium)),
                          Text(Role.labelOf(a.s('role')), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (st.role.canRunMeetings)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Meeting Transactions'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => showPaymentDialog(context, purpose: Purpose.shares, channel: Channel.cash),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Buy Shares'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => showPaymentDialog(context, purpose: Purpose.fine, channel: Channel.cash),
                      icon: const Icon(Icons.gavel, size: 16),
                      label: const Text('Collect Fine'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => showPaymentDialog(context, purpose: Purpose.loanRepayment, channel: Channel.cash),
                      icon: const Icon(Icons.payments, size: 16),
                      label: const Text('Loan Repayment'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => showPaymentDialog(context, purpose: Purpose.emergencyContribution, channel: Channel.cash),
                      icon: const Icon(Icons.health_and_safety, size: 16),
                      label: const Text('Emergency'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cash recorded by an officer during an open meeting posts at once, because the room is the witness.',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
        ],
        const SectionTitle('Meeting History', info: 'quorum'),
        if (past.isEmpty) const EmptyNote('No completed meetings in this cycle yet.'),
        for (final m in past)
          SaccoCard(
            radius: 12,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text('Meeting #${m.i('meeting_number')} • ${Dates.day(m['meeting_date'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Pill(text: st.t('Cash Reconciled'), color: okGreenBg, foreground: okGreen),
                  ],
                ),
                Text('Closing Cash Box: ${money(context, m.i('closing_cash'))}', style: tt.bodySmall?.copyWith(color: cs.primary)),
                Text('Present: ${m.l('attendance').where((a) => a.b('present')).length}/${m.l('attendance').length}', style: tt.bodySmall),
                if (m.n('minutes') != null) Text('Minutes: ${m.s('minutes')}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }

  /// Opening and closing a meeting: two people count the cash. Closing also takes the minutes.
  void _cashCount(BuildContext context, AppState st, {Json? closing}) {
    final members = st.activeMembers;
    final cash = TextEditingController(text: closing == null ? Money.plain(st.dash.i('cash_box'), st.currency) : '');
    final minutes = TextEditingController();
    String? c1 = closing?.n('opening_counter1') ?? st.myMemberId;
    String? c2 = closing?.n('opening_counter2');
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: closing == null ? 'Open Meeting' : 'Reconcile & Close Meeting',
        confirm: closing == null ? 'Confirm Opening Cash & Open' : 'Adjourn & Lock Cash Box',
        fields: (ctx, set) => [
          Text(closing == null
              ? 'Ledger says the lockbox holds ${Money.format(st.dash.i('cash_box'), st.currency)}. Two people count it now.'
              : 'The meeting closes only if the counted cash equals the ledger cash.'),
          MoneyField(controller: cash, label: 'Physical cash counted', currency: st.currency),
          MemberPicker(label: 'Counter 1', value: c1, members: members, onChanged: (v) => set(() => c1 = v)),
          MemberPicker(label: 'Counter 2', value: c2, members: members, onChanged: (v) => set(() => c2 = v)),
          if (closing != null) TextField(controller: minutes, maxLines: 3, decoration: const InputDecoration(labelText: 'Meeting Minutes / Notes')),
        ],
        onConfirm: (ctx) async {
          final v = Money.parse(cash.text, st.currency, true);
          if (v == null || c1 == null || c2 == null) return showMsg(ctx, 'Enter the cash and choose two counters.', error: true);
          await runAndClose(
            ctx,
            () => closing == null ? st.api.openMeeting(st.orgId, v, c1!, c2!) : st.api.closeMeeting(closing.s('id'), v, c1!, c2!, minutes.text),
            done: closing == null ? 'Meeting opened.' : 'Meeting closed. Cash matches.',
          );
        },
      ),
    );
  }
}
