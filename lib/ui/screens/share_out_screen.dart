import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/share_out.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class ShareOutScreen extends StatefulWidget {
  const ShareOutScreen({super.key});
  @override
  State<ShareOutScreen> createState() => _ShareOutScreenState();
}

class _ShareOutScreenState extends State<ShareOutScreen> {
  String? example; // 'A' or 'B' shows the worked examples

  static const exA = [ShareOutInput('ann', 'Ann Namubiru', 20000), ShareOutInput('ben', 'Ben Okello', 10000), ShareOutInput('cy', 'Cy Mugisha', 10000)];
  static const exB = [ShareOutInput('a', 'Member A', 10), ShareOutInput('b', 'Member B', 10), ShareOutInput('c', 'Member C', 10)];

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return FutureBuilder<Json>(
      key: ValueKey('${st.orgId}-${st.journals.length}-${st.org?.i('cycle_number')}'),
      future: st.api.shareOutPreview(st.orgId),
      builder: (context, snap) {
        if (snap.hasError) return AppPageView(children: [Text(snap.error.toString())]);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return _body(context, st, snap.data!);
      },
    );
  }

  Widget _body(BuildContext context, AppState st, Json live) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final int pool;
    final List<ShareOutRow> rows;
    if (example == 'A') {
      pool = 40083;
      rows = ShareOut.calculate(pool, exA);
    } else if (example == 'B') {
      pool = 100;
      rows = ShareOut.calculate(pool, exB);
    } else {
      pool = live.i('pool');
      rows = [for (final p in live.l('payouts')) ShareOutRow(p.s('member_id'), p.s('full_name'), p.i('savings'), p.i('payout'), p.b('bonus'))];
    }
    final sum = rows.fold<int>(0, (a, r) => a + r.payout);
    final exact = sum == pool && rows.isNotEmpty;
    final blockers = (live['blockers'] as List?) ?? const [];

    return AppPageView(children: [
      SaccoCard(
        color: cs.primaryContainer,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
                child: Text(example == null ? 'Cycle ${st.org!.i('cycle_number')} Share-Out' : 'Worked Example $example',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer))),
            Icon(Icons.calculate, color: cs.onPrimaryContainer),
          ]),
          Text('Largest Remainder: each member gets their exact whole-shilling share.',
              style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.9))),
          gap,
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Distributable Pool', style: tt.labelSmall),
              Text(Money.format(pool, st.currency), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Emergency Pot (Carried)', style: tt.labelSmall),
              Text(Money.format(example == 'A' ? 5000 : (example == 'B' ? 0 : live.i('emergency')), st.currency),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ]),
        ]),
      ),
      SaccoCard(
        color: exact || rows.isEmpty ? okGreenBg : cs.errorContainer,
        child: Row(children: [
          Icon(exact || rows.isEmpty ? Icons.verified : Icons.error, color: exact || rows.isEmpty ? okGreen : cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exact ? 'EXACT WHOLE-CURRENCY BALANCE PROVEN' : (rows.isEmpty ? 'NOTHING TO SHARE YET' : 'BALANCE ERROR'),
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: exact || rows.isEmpty ? okGreen : cs.error)),
              Text('Sum of member payouts ($sum) and pool ($pool). Remainder ${pool - sum}.',
                  style: tt.labelSmall?.copyWith(color: exact || rows.isEmpty ? okGreen : cs.error)),
            ]),
          ),
        ]),
      ),
      SaccoCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Interactive Benchmark Validations', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => setState(() => example = 'A'), child: const Text('Example A (Ann, Ben, Cy)')),
            OutlinedButton(onPressed: () => setState(() => example = 'B'), child: const Text('Example B (Pool 100 -> 34, 33, 33)')),
            if (example != null) TextButton(onPressed: () => setState(() => example = null), child: const Text('Reset to Live Group')),
          ]),
        ]),
      ),
      if (example == null && blockers.isNotEmpty)
        SaccoCard(
          color: cs.errorContainer,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Not ready to close. Figures below can still change.',
                style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onErrorContainer)),
            for (final b in blockers) Text('• $b', style: tt.bodySmall?.copyWith(color: cs.onErrorContainer)),
          ]),
        ),
      const SectionTitle('Member Payout Allocation Table'),
      if (rows.isEmpty) const EmptyNote('No savings recorded yet.'),
      for (final r in rows)
        SaccoCard(
          radius: 12,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('Saved ${Money.format(r.savings, st.currency)}${r.bonus ? ' • +1 remainder unit' : ''}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.format(r.payout, st.currency), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
              Text('Profit ${Money.format(r.profit, st.currency)}', style: tt.labelSmall),
            ]),
          ]),
        ),
      if (example == null && st.canReview && rows.isNotEmpty) ...[
        FilledButton.icon(
          onPressed: blockers.isNotEmpty ? null : () => _confirm(context, st, pool),
          icon: const Icon(Icons.lock),
          label: const Text('Close Cycle & Record Share-Out'),
        ),
      ],
    ]);
  }

  void _confirm(BuildContext context, AppState st, int pool) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cycle Share-Out'),
        content: Text('This records paying out ${Money.format(pool, st.currency)} and starts a new cycle. It cannot be reversed. '
            'Pay members from the group\'s own money. The app does not send it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => runAndClose(ctx, st, () async {
              await st.api.executeShareOut(st.orgId);
              await st.loadOrgs(select: st.orgId);
            }, done: 'Cycle closed.'),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
