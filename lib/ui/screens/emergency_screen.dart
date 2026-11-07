import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'channels_screen.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AppPageView(
      children: [
        SaccoCard(
          color: cs.secondaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Emergency Fund',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSecondaryContainer),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                money(context, st.dash.i('emergency_fund')),
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onSecondaryContainer),
              ),
              Text('Isolated from lending. Carries forward across cycles.', style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer)),
              gap,
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: st.myMemberId == null ? null : () => showPaymentDialog(context, purpose: Purpose.emergencyContribution),
                      child: const Text('Contribute'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(onPressed: st.myMemberId == null ? null : () => _claim(context, st), child: const Text('Claim Relief')),
                  ),
                ],
              ),
            ],
          ),
        ),
        SaccoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Eligible Emergency Relief Cases', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                '• Sudden medical hospitalization of member\n• Bereavement assistance (funeral contribution)\n• Natural disaster / structural home destruction',
              ),
            ],
          ),
        ),
        const SectionTitle('Relief Claims', info: 'emergency_fund'),
        if (st.claims.isEmpty) const EmptyNote('No claims yet.'),
        for (final c in st.claims)
          SaccoCard(
            radius: 12,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${c.s('member_name')} • ${money(context, c.i('amount'))}', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    StatusPill(c.s('status')),
                  ],
                ),
                Text(c.s('reason'), style: tt.bodySmall),
                Text(Dates.dayTime(c['requested_at']), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                if (c.n('decided_by_name') != null)
                  Text(
                    'Decided by ${c.s('decided_by_name')}${c.n('decision_note') != null ? ': ${c.s('decision_note')}' : ''}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                if (c.s('status') == 'pending' && st.role.handlesMoney)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => _reject(context, st, c), child: const Text('Reject')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: () => _pay(context, st, c), child: const Text('Record Payment')),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _claim(BuildContext context, AppState st) {
    final amount = TextEditingController();
    final reason = TextEditingController();
    String? member = st.myMemberId;
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Claim Emergency Relief',
        confirm: 'Send Claim',
        fields: (ctx, set) => [
          if (st.role.canRunMeetings)
            MemberPicker(label: 'Beneficiary Member', value: member, members: st.activeMembers, onChanged: (v) => set(() => member = v)),
          MoneyField(controller: amount, label: 'Relief Amount', currency: st.currency),
          TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Emergency Justification'),
          ),
        ],
        onConfirm: (ctx) async {
          final a = Money.parse(amount.text, st.currency);
          if (a == null || member == null) {
            showMsg(ctx, 'Enter the amount.', error: true);
            return;
          }
          await runAndClose(ctx, () => st.api.requestEmergency(st.orgId, member!, a, reason.text), done: 'Claim sent.');
        },
      ),
    );
  }

  Future<void> _reject(BuildContext context, AppState st, Json c) async {
    final r = await askText(context, title: 'Reject claim', label: 'Why?', confirm: 'Reject');
    if (r == null || !context.mounted) return;
    await runAndTell(context, () => st.api.decideEmergency(c.s('id'), false, null, null, r));
  }

  void _pay(BuildContext context, AppState st, Json c) {
    var channel = Channel.cash;
    final ref = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Record Relief Payment',
        confirm: 'Record',
        fields: (ctx, set) => [
          Text('Pay ${Money.format(c.i('amount'), st.currency)} to ${c.s('member_name')} from the group\'s own money, then record it here.'),
          ChannelFields(value: channel, ref: ref, onChanged: (v) => set(() => channel = v)),
        ],
        onConfirm: (ctx) async {
          final problem = ChannelFields.problem(channel, ref);
          if (problem != null) return showMsg(ctx, problem, error: true);
          await runAndClose(ctx, () => st.api.decideEmergency(c.s('id'), true, channel.code, ChannelFields.refFor(channel, ref), ''), done: 'Relief recorded.');
        },
      ),
    );
  }
}
