import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/share_out.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text.dart';

class ShareOutScreen extends StatelessWidget {
  const ShareOutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return Loaded<Json>(load: () => st.api.shareOutPreview(st.orgId), builder: (context, live) => _body(context, st, live));
  }

  /// End of cycle: how much there is to share, who gets what, and one button to close the cycle.
  Widget _body(BuildContext context, AppState st, Json live) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final pool = live.i('pool');
    final rows = [for (final p in live.l('payouts')) ShareOutRow(p.s('member_id'), p.s('full_name'), p.i('savings'), p.i('payout'), p.b('bonus'))];
    final sum = rows.fold<int>(0, (a, r) => a + r.payout);
    final exact = sum == pool && rows.isNotEmpty;
    final blockers = (live['blockers'] as List?) ?? const [];

    return AppPageView(
      children: [
        SaccoCard(
          color: look.brand,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cycle ${st.org!.i('cycle_number')} share-out', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: look.onBrand)),
              const SizedBox(height: 12),
              Text('Money to share', style: tt.bodyMedium?.copyWith(color: look.onBrandMuted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Money.format(pool, st.currency), style: look.numbers(tt.headlineMedium).copyWith(color: look.onBrand, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              Text('The emergency fund (${Money.format(live.i('emergency'), st.currency)}) stays for next cycle.',
                  style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
            ],
          ),
        ),
        if (blockers.isNotEmpty)
          _Note(
            icon: Icons.hourglass_top_rounded,
            color: cs.errorContainer,
            fg: cs.onErrorContainer,
            title: 'Not ready to close yet',
            lines: [for (final b in blockers) '$b'],
          )
        else if (rows.isNotEmpty)
          _Note(
            icon: exact ? Icons.verified_rounded : Icons.error_rounded,
            color: exact ? look.okBg : cs.errorContainer,
            fg: exact ? look.ok : cs.onErrorContainer,
            title: exact ? 'Checked: the shares add up exactly' : 'The shares do not add up',
            lines: [
              exact
                  ? 'Every shilling is given out. Nothing is left over or missing.'
                  : 'Shares ${Money.format(sum, st.currency)}, pot ${Money.format(pool, st.currency)}. Do not close. Tell the platform team.'
            ],
          ),
        const SectionTitle('Who gets what', info: 'share_out'),
        if (rows.isEmpty) const EmptyNote('Nothing to share yet. Savings show here once members pay.'),
        for (final r in rows)
          SaccoCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Saved ${Money.format(r.savings, st.currency)}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Money.format(r.payout, st.currency), style: look.numbers(tt.titleMedium).copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
                    const SizedBox(height: 2),
                    Text(
                      r.profit >= 0 ? 'Gain ${Money.format(r.profit, st.currency)}' : 'Less than saved: ${Money.format(-r.profit, st.currency)}',
                      style: tt.bodySmall?.copyWith(color: r.profit >= 0 ? look.ok : cs.error),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (rows.any((r) => r.profit < 0))
          Text('"Less than saved" happens when some money is still out as loans. It comes back as loans are repaid.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (st.role.handlesMoney && rows.isNotEmpty)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: blockers.isNotEmpty ? null : () => _confirm(context, st, pool),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Close the cycle and record the share-out'),
          ),
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
            onPressed: () => runAndClose(ctx, () => st.api.executeShareOut(st.orgId), done: 'Cycle closed.'),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

/// A coloured note with an icon, a bold line and plain lines under it.
class _Note extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color fg;
  final String title;
  final List<String> lines;
  const _Note({required this.icon, required this.color, required this.fg, required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SaccoCard(
      color: color,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: fg)),
            for (final l in lines) Text(l, style: tt.bodyMedium?.copyWith(color: fg)),
          ]),
        ),
      ]),
    );
  }
}
