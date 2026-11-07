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

/// A worked example: made-up members, so people can check the rule by hand.
class _Example {
  final String name;
  final String button;
  final int pool;
  final int emergency;
  final List<ShareOutInput> members;
  const _Example(this.name, this.button, this.pool, this.emergency, this.members);
}

const _examples = [
  _Example('A', 'Example A (Ann, Ben, Cy)', 40083, 5000,
      [ShareOutInput('ann', 'Ann Namubiru', 20000), ShareOutInput('ben', 'Ben Okello', 10000), ShareOutInput('cy', 'Cy Mugisha', 10000)]),
  _Example('B', 'Example B (Pool 100 -> 34, 33, 33)', 100, 0, [ShareOutInput('a', 'Member A', 10), ShareOutInput('b', 'Member B', 10), ShareOutInput('c', 'Member C', 10)]),
];

class _ShareOutScreenState extends State<ShareOutScreen> {
  _Example? example;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return Loaded<Json>(load: () => st.api.shareOutPreview(st.orgId), builder: (context, live) => _body(context, st, live));
  }

  Widget _body(BuildContext context, AppState st, Json live) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ex = example;
    final pool = ex?.pool ?? live.i('pool');
    final rows = ex != null
        ? ShareOut.calculate(ex.pool, ex.members)
        : [for (final p in live.l('payouts')) ShareOutRow(p.s('member_id'), p.s('full_name'), p.i('savings'), p.i('payout'), p.b('bonus'))];
    final sum = rows.fold<int>(0, (a, r) => a + r.payout);
    final exact = sum == pool && rows.isNotEmpty;
    final blockers = (live['blockers'] as List?) ?? const [];

    return AppPageView(
      children: [
        SaccoCard(
          color: cs.primaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      ex == null ? 'Cycle ${st.org!.i('cycle_number')} Share-Out' : 'Worked Example ${ex.name}',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                    ),
                  ),
                  Icon(Icons.calculate, color: cs.onPrimaryContainer),
                ],
              ),
              Text(
                'Largest Remainder: each member gets their exact whole-shilling share.',
                style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.9)),
              ),
              gap,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distributable Pool', style: tt.labelSmall),
                      Text(
                        Money.format(pool, st.currency),
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Emergency Pot (Carried)', style: tt.labelSmall),
                      Text(
                        Money.format(ex?.emergency ?? live.i('emergency'), st.currency),
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        SaccoCard(
          color: exact || rows.isEmpty ? okGreenBg : cs.errorContainer,
          child: Row(
            children: [
              Icon(exact || rows.isEmpty ? Icons.verified : Icons.error, color: exact || rows.isEmpty ? okGreen : cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exact ? 'EXACT WHOLE-CURRENCY BALANCE PROVEN' : (rows.isEmpty ? 'NOTHING TO SHARE YET' : 'BALANCE ERROR'),
                      style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: exact || rows.isEmpty ? okGreen : cs.error),
                    ),
                    Text(
                      'Sum of member payouts ($sum) and pool ($pool). Remainder ${pool - sum}.',
                      style: tt.labelSmall?.copyWith(color: exact || rows.isEmpty ? okGreen : cs.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SaccoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Interactive Benchmark Validations', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _examples) OutlinedButton(onPressed: () => setState(() => example = e), child: Text(e.button)),
                  if (ex != null) TextButton(onPressed: () => setState(() => example = null), child: const Text('Reset to Live Group')),
                ],
              ),
            ],
          ),
        ),
        if (ex == null && blockers.isNotEmpty)
          SaccoCard(
            color: cs.errorContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not ready to close. Figures below can still change.',
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onErrorContainer),
                ),
                for (final b in blockers) Text('• $b', style: tt.bodySmall?.copyWith(color: cs.onErrorContainer)),
              ],
            ),
          ),
        const SectionTitle('Member Payout Allocation Table', info: 'share_out'),
        if (rows.isEmpty) const EmptyNote('No savings recorded yet.'),
        for (final r in rows)
          SaccoCard(
            radius: 12,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        'Saved ${Money.format(r.savings, st.currency)}${r.bonus ? ' • +1 remainder unit' : ''}',
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.format(r.payout, st.currency),
                      style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                    ),
                    Text('Profit ${Money.format(r.profit, st.currency)}', style: tt.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        if (ex == null && st.role.handlesMoney && rows.isNotEmpty) ...[
          FilledButton.icon(
            onPressed: blockers.isNotEmpty ? null : () => _confirm(context, st, pool),
            icon: const Icon(Icons.lock),
            label: const Text('Close Cycle & Record Share-Out'),
          ),
        ],
      ],
    );
  }

  void _confirm(BuildContext context, AppState st, int pool) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cycle Share-Out'),
        content: Text(
          'This records paying out ${Money.format(pool, st.currency)} and starts a new cycle. It cannot be reversed. '
          'Pay members from the group\'s own money. The app does not send it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => runAndClose(ctx, st, () => st.api.executeShareOut(st.orgId), done: 'Cycle closed.'),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
