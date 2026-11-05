import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../widgets.dart';
import 'channels_screen.dart';

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
        if (r == null) return;
        note = r;
      }
      final err = await st.act(() => st.api.reviewPayment(p.s('id'), approve, note));
      if (context.mounted) showMsg(context, err ?? (approve ? 'Confirmed and posted to the ledger.' : 'Rejected.'), error: err != null);
    }

    return AppPageView(children: [
      SectionTitle('Waiting for review (${pending.length})',
          trailing: st.myMemberId == null
              ? null
              : TextButton.icon(onPressed: () => showRecordPayment(context), icon: const Icon(Icons.add), label: const Text('Record'))),
      if (pending.isEmpty) const EmptyNote('Nothing waiting. All records are checked.'),
      for (final p in pending)
        PaymentTile(p, actions: [
          if (st.canReview) ...[
            TextButton(onPressed: () => decide(p, false), child: const Text('Reject')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => decide(p, true), child: const Text('Confirm')),
          ],
        ]),
      const SectionTitle('Reviewed'),
      for (final p in done) PaymentTile(p),
    ]);
  }
}
