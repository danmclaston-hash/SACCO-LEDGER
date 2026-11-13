import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/risk.dart';
import '../charts.dart';
import '../theme.dart';
import '../widgets.dart';

/// How the group is doing, for officers: money held, loan health in plain words, charts and tips.
/// Moved off the home page so the home answers only "what needs me now".
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final d = st.dash;
    final m = RiskEngine.metrics(d);
    final tips = RiskEngine.flags(d, m);
    final (String word, Color color) = m.score >= 80 ? ('Healthy', look.ok) : (m.score >= 60 ? ('Needs care', look.warn) : ('At risk', cs.error));

    return AppPageView(
      children: [
        Text('How the group is doing', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SectionTitle('Where the money is', info: 'double_entry'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            BalanceStatCard(
                title: 'Cash box',
                amount: money(context, d.i('cash_box')),
                subtitle: 'Counted at meetings',
                icon: Icons.savings_outlined,
                color: cs.surfaceContainerHighest),
            BalanceStatCard(
                title: 'Mobile money and bank',
                amount: money(context, d.i('momo_bank')),
                subtitle: 'The group\'s own accounts',
                icon: Icons.phone_android,
                color: cs.surfaceContainerHighest),
            BalanceStatCard(
                title: 'Member savings',
                amount: money(context, d.i('member_savings')),
                subtitle: '${d.i('members_active')} members',
                icon: Icons.account_balance_wallet_outlined,
                color: cs.surfaceContainerHighest),
            BalanceStatCard(
                title: 'Out as loans',
                amount: money(context, d.i('loan_portfolio')),
                subtitle: '${d.i('loans_total')} ${d.i('loans_total') == 1 ? 'loan' : 'loans'}',
                icon: Icons.payments_outlined,
                color: cs.surfaceContainerHighest),
          ],
        ),
        SaccoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Loan health', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              Pill(text: '$word • ${m.score}/100', color: color, foreground: Colors.white),
            ]),
            const SizedBox(height: 12),
            _Line('Money in loans 30+ days late', '${m.par30.toStringAsFixed(1)}%', m.par30Alert),
            _Line('Money in loans 90+ days late', '${m.par90.toStringAsFixed(1)}%', m.par90Alert),
            _Line('Cash ready to use', '${m.liquidity.toStringAsFixed(1)}%', m.liquidityAlert),
            _Line('Repayments paid on time this month', '${m.collection.toStringAsFixed(1)}%', m.collectionAlert),
          ]),
        ),
        if (tips.isNotEmpty)
          SaccoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tips', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Simple rules from your numbers. The app never acts on money.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final f in tips)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                      switch (f.severity) {
                        RiskSeverity.high => Icons.error_rounded,
                        RiskSeverity.medium => Icons.warning_rounded,
                        RiskSeverity.low => Icons.check_circle_rounded,
                      },
                      size: 20,
                      color: switch (f.severity) {
                        RiskSeverity.high => cs.error,
                        RiskSeverity.medium => look.warn,
                        RiskSeverity.low => look.ok,
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        Text(f.recommendation, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        if (st.flows.any((f) => f.i('paid_in') > 0 || f.i('paid_out') > 0 || f.i('savings') > 0)) ...[
          const SectionTitle('Month by month'),
          MoneyFlowChart(flows: st.flows, currency: st.currency, mine: false),
          SavingsGrowthChart(flows: st.flows, currency: st.currency, mine: false),
        ],
      ],
    );
  }
}

/// A plain sentence on the left, the number on the right, red when it needs attention.
class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const _Line(this.label, this.value, this.alert);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: tt.bodyMedium)),
        if (alert) Icon(Icons.warning_rounded, size: 18, color: cs.error),
        const SizedBox(width: 4),
        Text(value, style: SaccoLook.of(context).numbers(tt.titleSmall).copyWith(fontWeight: FontWeight.w700, color: alert ? cs.error : cs.onSurface)),
      ]),
    );
  }
}
