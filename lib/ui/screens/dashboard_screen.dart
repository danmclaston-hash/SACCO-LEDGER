import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/pages.dart';
import '../motion.dart';
import '../theme.dart';
import '../tour.dart';
import '../widgets.dart';
import 'channels_screen.dart';
import 'goals_screen.dart';
import 'home_screen.dart';
import 'needs_you.dart';
import '../text.dart';

/// An officer's home. Three questions, in this order:
/// 1. What needs me now?  2. How much money does the group have?  3. What do I do next?
/// Charts, health scores and tips live on the Reports page, so this page stays short.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    if (!st.role.isOfficer && !st.canSeeAllGroups) return const MemberHome();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final d = st.dash;
    final org = st.org!;
    final first = (st.me?.s('full_name') ?? st.account.s('full_name')).trim().split(' ').first;
    final held = d.i('cash_box') + d.i('momo_bank');
    final recent = st.journals.take(3).toList();
    final goal = st.activeGoals.firstOrNull;

    return AppPageView(
      children: [
        RiseIn(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(first.isEmpty ? org.s('name') : 'Hello, $first', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${st.role == Role.orgAdmin ? 'Admin' : st.role.label} • Cycle ${org.i('cycle_number')}',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            if (org.b('is_demo')) Padding(padding: const EdgeInsets.only(top: 8), child: Pill(text: 'DEMO: not real money', color: look.warn)),
          ]),
        ),
        const RiseIn(delay: Duration(milliseconds: 40), child: NeedsYouCard()),
        RiseIn(
          delay: const Duration(milliseconds: 80),
          child: TourTarget.money.wrap(Material(
            color: look.brand,
            borderRadius: BorderRadius.circular(look.radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: st.canSee(AppPage.reports) ? () => st.goTo(AppPage.reports) : null,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('The group holds', style: tt.bodyMedium?.copyWith(color: look.onBrandMuted))),
                    if (st.canSee(AppPage.reports)) Text('Reports ›', style: tt.labelLarge?.copyWith(color: look.onBrand, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money(context, held),
                        style: look.numbers(tt.displaySmall).copyWith(color: look.onBrand, fontWeight: FontWeight.w800, fontSize: 34)),
                  ),
                  Text('Cash box ${Money.format(d.i('cash_box'), st.currency)} • Mobile money and bank ${Money.format(d.i('momo_bank'), st.currency)}',
                      style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _Figure('Savings', money(context, d.i('member_savings'))),
                    _Figure('Out as loans', money(context, d.i('loan_portfolio'))),
                    _Figure('Emergency', money(context, d.i('emergency_fund'))),
                  ]),
                ]),
              ),
            ),
          )),
        ),
        RiseIn(
          delay: const Duration(milliseconds: 120),
          child: TourTarget.actions.wrap(LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 20) / 3;
            return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              BigTile(
                width: w,
                height: 104,
                icon: Icons.edit_note_rounded,
                label: 'Record',
                main: true,
                onTap: st.role.canRunMeetings ? () => showPaymentDialog(context) : () => st.goTo(AppPage.channels),
              ),
              BigTile(width: w, height: 104, icon: Icons.groups_rounded, label: st.t('Meetings'), onTap: () => st.goTo(AppPage.meetings)),
              BigTile(width: w, height: 104, icon: Icons.payments_outlined, label: st.t('Loans'), onTap: () => st.goTo(AppPage.loans)),
            ]);
          })),
        ),
        if (goal != null) ...[
          SectionTitle('Goal', trailing: TextButton(onPressed: () => st.goTo(AppPage.goals), child: const Text('All goals'))),
          GoalCard(goal),
        ],
        if (recent.isNotEmpty) ...[
          SectionTitle('Latest records', trailing: TextButton(onPressed: () => st.goTo(AppPage.ledger), child: const Text('See all'))),
          SaccoCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final (i, j) in recent.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  minTileHeight: 56,
                  title: Text(j.s('description'), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(Dates.dayTime(j['created_at'])),
                  trailing: Text(money(context, j.i('total')), style: look.numbers(tt.titleSmall).copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}

/// One small labelled number on the money card.
class _Figure extends StatelessWidget {
  final String label;
  final String value;
  const _Figure(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final look = SaccoLook.of(context);
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: look.numbers(tt.titleSmall).copyWith(color: look.onBrand, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
