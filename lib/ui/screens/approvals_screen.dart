import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'channels_screen.dart';
import '../text.dart';

/// Two people rule: someone other than the person who recorded it checks it against the MoMo or bank statement.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final pending = st.payments.where((p) => p.s('status') == 'pending').toList();
    final done = st.payments.where((p) => p.s('status') != 'pending').take(50).toList();

    Future<void> decide(Json p, bool approve) async {
      var note = '';
      if (!approve) {
        final r = await askText(context, title: 'Reject this record', label: 'Why?', confirm: 'Reject');
        if (r == null || !context.mounted) return;
        note = r;
      }
      await runAndTell(context, () => st.api.reviewPayment(p.s('id'), approve, note), done: approve ? 'Confirmed and posted to the ledger.' : 'Rejected.');
    }

    return AppPageView(
      children: [
        SectionTitle(
          'Waiting for review (${pending.length})',
          trailing: st.myMemberId == null
              ? null
              : TextButton.icon(onPressed: () => showPaymentDialog(context), icon: const Icon(Icons.add), label: const Text('Record')),
        ),
        if (pending.isEmpty) const EmptyNote('Nothing waiting. All records are checked.'),
        for (final p in pending)
          PaymentTile(
            p,
            actions: [
              if (st.role.handlesMoney) ...[
                TextButton(onPressed: () => decide(p, false), child: const Text('Reject')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => decide(p, true), child: const Text('Confirm')),
              ],
            ],
          ),
        const SectionTitle('Reviewed', info: 'two_person'),
        for (final p in done)
          PaymentTile(p, actions: [
            // Fix a forgotten or wrong goal label. The money does not move; the audit trail keeps who and why.
            if (st.role.canRunMeetings &&
                p.s('status') == 'confirmed' &&
                Purpose.parse(p.s('purpose')).takesGoal &&
                (st.activeGoals.isNotEmpty || p.n('goal_id') != null))
              TextButton.icon(onPressed: () => _relabel(context, st, p), icon: const Icon(Icons.flag_outlined, size: 16), label: const Text('Goal label')),
          ]),
      ],
    );
  }
}

void _relabel(BuildContext context, AppState st, Json p) {
  String? goal = p.n('goal_id');
  final reason = TextEditingController();
  showDialog(
    context: context,
    builder: (_) => FormDialog(
      title: 'Change goal label',
      confirm: 'Save',
      fields: (ctx, set) => [
        Text('${p.s('member_name')} • ${Money.format(p.i('amount'), st.currency)}. The money stays in savings. Only the label changes.'),
        // A closed goal stays in the list, so saving without a change keeps its label.
        GoalPicker(
          label: 'For goal',
          value: goal,
          goals: [...st.activeGoals, ...st.goals.where((g) => g.s('id') == goal && g.s('status') != 'active')],
          onChanged: (v) => set(() => goal = v),
        ),
        TextField(controller: reason, decoration: InputDecoration(labelText: 'Why? (kept in the audit trail)')),
      ],
      onConfirm: (ctx) => runAndClose(ctx, () => st.api.setPaymentGoal(p.s('id'), goal, reason.text), done: 'Label changed and recorded.'),
    ),
  );
}
