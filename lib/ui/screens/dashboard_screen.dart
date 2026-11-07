import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/risk.dart';
import '../../core/search_index.dart';
import '../charts.dart';
import '../theme.dart';
import 'goals_screen.dart';
import '../widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = st.dash;
    final org = st.org!;
    final metrics = RiskEngine.metrics(d);
    final flags = RiskEngine.flags(d, metrics);
    final pending = d.i('pending_payments') + d.i('pending_loans') + d.i('pending_emergency');
    final recent = st.journals.take(4).toList();
    final me = st.me;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          org.s('name'),
                          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                        ),
                        Text(
                          'Cycle ${org.i('cycle_number')} • ${editionNames[org.s('edition')]}',
                          style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: cs.primary,
                    child: Icon(Icons.shield, color: cs.secondary),
                  ),
                ],
              ),
              gap,
              Text(editionHints[org.s('edition')] ?? '', style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.9))),
            ],
          ),
        ),
        if (org.b('is_demo'))
          const Align(
            alignment: Alignment.centerLeft,
            child: Pill(text: 'DEMO DATA: not real money', color: warnOrange),
          ),
        if (me != null && !st.isOfficer)
          SaccoCard(
            color: cs.secondaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('My savings', style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const InfoTip('savings'),
                ]),
                Text(money(context, me.i('savings')), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('${org.i('share_price') > 0 ? me.i('savings') ~/ org.i('share_price') : 0} shares', style: tt.labelSmall),
              ],
            ),
          ),
        if (st.isOfficer && pending > 0)
          SaccoCard(
            color: cs.errorContainer,
            child: Row(
              children: [
                Icon(Icons.pending_actions, color: cs.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$pending record(s) wait for review',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.onErrorContainer),
                  ),
                ),
                TextButton(onPressed: () => st.goTo(AppPage.approvals), child: const Text('Review')),
              ],
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Financial Position (Double-Entry Balanced)', info: 'double_entry'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: BalanceStatCard(
                    title: 'Cash in Lockbox',
                    amount: money(context, d.i('cash_box')),
                    subtitle: 'MoMo/Bank: ${money(context, d.i('momo_bank'))}',
                    icon: Icons.savings,
                    color: cs.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BalanceStatCard(
                    title: 'Member Savings',
                    amount: money(context, d.i('member_savings')),
                    subtitle: '${d.i('members_active')} Members Active',
                    icon: Icons.account_balance_wallet,
                    color: cs.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: BalanceStatCard(
                    title: 'Loan Portfolio',
                    amount: money(context, d.i('loan_portfolio')),
                    subtitle: '${d.i('loans_total')} Total Loans',
                    icon: Icons.request_quote,
                    color: cs.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BalanceStatCard(
                    title: 'Emergency Fund',
                    amount: money(context, d.i('emergency_fund')),
                    subtitle: 'Isolated Welfare Pot',
                    icon: Icons.health_and_safety,
                    color: cs.secondaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: st.isPlatformAdmin ? null : () => st.goTo(AppPage.channels),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('Record Payment'),
            ),
            FilledButton.tonalIcon(onPressed: () => st.goTo(AppPage.meetings), icon: const Icon(Icons.groups, size: 16), label: const Text('Meeting')),
            FilledButton.tonalIcon(onPressed: () => st.goTo(AppPage.goals), icon: const Icon(Icons.flag, size: 16), label: Text(st.t('goals'))),
            OutlinedButton.icon(onPressed: () => st.goTo(AppPage.loans), icon: const Icon(Icons.credit_score, size: 16), label: const Text('Loans')),
            OutlinedButton.icon(onPressed: () => st.goTo(AppPage.statements), icon: const Icon(Icons.receipt_long, size: 16), label: const Text('Statements')),
            if (st.isOfficer)
              OutlinedButton.icon(onPressed: () => st.goTo(AppPage.approvals), icon: const Icon(Icons.fact_check, size: 16), label: const Text('Approvals')),
            if (st.isOfficer)
              OutlinedButton.icon(onPressed: () => st.goTo(AppPage.members), icon: const Icon(Icons.people, size: 16), label: Text(st.t('members'))),
            OutlinedButton.icon(onPressed: () => st.goTo(AppPage.licences), icon: const Icon(Icons.verified, size: 16), label: const Text('Licences')),
            if (st.isOfficer)
              OutlinedButton.icon(onPressed: () => st.goTo(AppPage.settings), icon: const Icon(Icons.settings, size: 16), label: const Text('Settings')),
            if (!st.isOfficer) OutlinedButton.icon(onPressed: st.signOut, icon: const Icon(Icons.logout, size: 16), label: const Text('Sign out')),
          ],
        ),
        // Goals running now: one line each, tap to open.
        if (st.activeGoals.isNotEmpty) ...[
          SectionTitle('Our goals', trailing: TextButton(onPressed: () => st.goTo(AppPage.goals), child: const Text('All goals'))),
          for (final g in st.activeGoals.take(3)) GoalCard(g),
        ],
        // How the group is doing: simple charts from checked records only.
        if (st.flows.any((f) => f.i('paid_in') > 0 || f.i('paid_out') > 0 || f.i('savings') > 0)) ...[
          SectionTitle(st.isOfficer ? 'How the group is doing' : 'How I am doing'),
          MoneyFlowChart(flows: st.flows, currency: st.currency, mine: !st.isOfficer),
          SavingsGrowthChart(flows: st.flows, currency: st.currency, mine: !st.isOfficer),
        ],
        SaccoCard(
          elevation: 2,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.analytics, color: cs.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('Portfolio Risk & Health', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  Pill(text: 'Score: ${metrics.score}/100', color: metrics.score >= 80 ? okGreen : (metrics.score >= 60 ? warnOrange : cs.error)),
                ],
              ),
              gap,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Metric('PAR 30', metrics.par30, metrics.par30 > 5),
                  _Metric('PAR 90', metrics.par90, metrics.par90 > 2),
                  _Metric('Liquidity', metrics.liquidity, metrics.liquidity < 15),
                  _Metric('Collection', metrics.collection, metrics.collection < 90),
                ],
              ),
            ],
          ),
        ),
        SaccoCard(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb, color: cs.secondary),
                  const SizedBox(width: 8),
                  Text('Advice (Heuristic Rules)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              Text(st.t('ai_notice'), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
              const SizedBox(height: 8),
              for (final f in flags)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (f.severity) {
                            RiskSeverity.high => cs.error,
                            RiskSeverity.medium => warnOrange,
                            RiskSeverity.low => okGreen,
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                            Text(f.recommendation, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              st.isOfficer ? 'Recent Journal Postings' : 'My Recent Records',
              trailing: TextButton(onPressed: () => st.goTo(AppPage.ledger), child: const Text('View Full Ledger')),
            ),
            if (recent.isEmpty) const EmptyNote('No journal entries recorded yet.'),
            for (final j in recent)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SaccoCard(
                  radius: 12,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${j.i('journal_number')} • ${j.s('type').toUpperCase()}',
                              style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                            ),
                            Text(j.s('description'), style: tt.bodySmall),
                          ],
                        ),
                      ),
                      Text(money(context, j.i('total')), style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final double value;
  final bool alert;
  const _Metric(this.title, this.value, this.alert);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(title, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(
          '${value.toStringAsFixed(1)}%',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: alert ? cs.error : cs.onSurface),
        ),
      ],
    );
  }
}
