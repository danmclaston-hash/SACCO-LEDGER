import 'package:flutter/material.dart';

import '../core/pages.dart';
import '../state/app_state.dart';
import 'screens/account_screen.dart';
import 'screens/approvals_screen.dart';
import 'screens/channels_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/emergency_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/ledger_screen.dart';
import 'screens/licences_screen.dart';
import 'screens/loans_screen.dart';
import 'screens/meetings_screen.dart';
import 'screens/members_screen.dart';
import 'screens/platform_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_out_screen.dart';
import 'screens/statements_screen.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'widgets.dart';

IconData pageIcon(AppPage p) => switch (p) {
      AppPage.overview => Icons.home_rounded,
      AppPage.approvals => Icons.fact_check,
      AppPage.goals => Icons.flag,
      AppPage.members => Icons.people,
      AppPage.meetings => Icons.groups,
      AppPage.loans => Icons.payments_outlined,
      AppPage.emergency => Icons.health_and_safety,
      AppPage.ledger => Icons.account_balance_wallet,
      AppPage.statements => Icons.receipt_long,
      AppPage.shareOut => Icons.calculate,
      AppPage.channels => Icons.arrow_circle_up_rounded,
      AppPage.licences => Icons.verified,
      AppPage.settings => Icons.settings,
      AppPage.account => Icons.account_circle,
      AppPage.platform => Icons.domain,
    };

Widget pageBody(AppPage p) => switch (p) {
      AppPage.account => const AccountScreen(),
      AppPage.goals => const GoalsScreen(),
      AppPage.overview => const DashboardScreen(),
      AppPage.approvals => const ApprovalsScreen(),
      AppPage.members => const MembersScreen(),
      AppPage.meetings => const MeetingsScreen(),
      AppPage.loans => const LoansScreen(),
      AppPage.emergency => const EmergencyScreen(),
      AppPage.ledger => const LedgerScreen(),
      AppPage.shareOut => const ShareOutScreen(),
      AppPage.channels => const ChannelsScreen(),
      AppPage.statements => const StatementsScreen(),
      AppPage.licences => const LicencesScreen(),
      AppPage.settings => const SettingsScreen(),
      AppPage.platform => const PlatformScreen(),
    };

/// Short fade between pages, so a tap clearly lands. Off when the phone asks for less motion.
Widget animatedPage(BuildContext context, AppPage p) => AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey(p), child: pageBody(p)),
    );

/// Phones and narrow browser windows: four tabs a thumb can reach, and "More" for everything else.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  static List<AppPage> tabsFor(AppState st) => st.role.isOfficer
      ? const [AppPage.overview, AppPage.approvals, AppPage.meetings, AppPage.loans]
      : const [AppPage.overview, AppPage.channels, AppPage.loans, AppPage.goals];

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tabs = tabsFor(st);
    final index = tabs.indexOf(st.page);
    final pending = st.dash['pending_payments'];
    Widget icon(AppPage p, {bool selected = false}) {
      final i = Icon(pageIcon(p), size: 26);
      return p == AppPage.approvals && pending is int && pending > 0 ? Badge(label: Text('$pending'), child: i) : i;
    }

    return PopScope(
      canPop: st.page == AppPage.overview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) st.goTo(AppPage.overview);
      },
      child: Scaffold(
        appBar: const TopBar(),
        body: Column(
          children: [
            if (st.loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: animatedPage(context, st.page)),
              ),
            ),
          ],
        ),
        // Labels stay on one line even with large text. Icons and page titles still grow.
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: NavigationBar(
              selectedIndex: index < 0 ? tabs.length : index,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (i) => i < tabs.length ? st.goTo(tabs[i]) : showMorePages(context),
              destinations: [
                for (final p in tabs) NavigationDestination(icon: icon(p), label: st.t(p.tab)),
                NavigationDestination(icon: const Icon(Icons.apps, size: 26), label: st.t('More')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every other page this person may open, as picture tiles.
Future<void> showMorePages(BuildContext context) {
  final st = StateScope.of(context);
  final tabs = MobileShell.tabsFor(st);
  final rest = AppPage.values.where((p) => !tabs.contains(p) && st.canSee(p)).toList();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final look = SaccoLook.of(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              for (final p in rest)
                Material(
                  color: p == st.page ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(look.radius * 0.8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(look.radius * 0.8),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      st.goTo(p);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(pageIcon(p), size: 30, color: cs.primary),
                          const SizedBox(height: 8),
                          Text(
                            st.t(p.tab),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Wide browser windows: a side menu with every page this person's role may open.
class WideShell extends StatelessWidget {
  const WideShell({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final items = AppPage.values.where(st.canSee).toList();
    final pending = st.dash['pending_payments'];
    Widget icon(AppPage p) =>
        p == AppPage.approvals && pending is int && pending > 0 ? Badge(label: Text('$pending'), child: Icon(pageIcon(p))) : Icon(pageIcon(p));

    return Scaffold(
      appBar: const TopBar(),
      body: Row(
        children: [
          Container(
            width: 232,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: cs.outlineVariant))),
            child: Material(
              color: cs.surface,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                children: [
                  for (final p in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SaccoLook.of(context).radius * 0.6)),
                        selected: p == st.page,
                        selectedColor: cs.onPrimaryContainer,
                        selectedTileColor: cs.primaryContainer,
                        leading: icon(p),
                        title: Text(st.t(p.title), style: TextStyle(fontWeight: p == st.page ? FontWeight.w700 : FontWeight.w500)),
                        onTap: () => st.goTo(p),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (st.loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: animatedPage(context, st.page)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
