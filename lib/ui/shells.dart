import 'package:flutter/material.dart';

import '../core/pages.dart';
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
import 'top_bar.dart';
import 'widgets.dart';

IconData pageIcon(AppPage p) => switch (p) {
      AppPage.overview => Icons.dashboard,
      AppPage.approvals => Icons.fact_check,
      AppPage.goals => Icons.flag,
      AppPage.members => Icons.people,
      AppPage.meetings => Icons.groups,
      AppPage.loans => Icons.request_quote,
      AppPage.emergency => Icons.health_and_safety,
      AppPage.ledger => Icons.account_balance_wallet,
      AppPage.statements => Icons.receipt_long,
      AppPage.shareOut => Icons.calculate,
      AppPage.channels => Icons.phone_iphone,
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

/// Phones: the same bottom bar as the original app.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  static const _tabs = [AppPage.overview, AppPage.meetings, AppPage.loans, AppPage.emergency, AppPage.ledger, AppPage.shareOut, AppPage.channels];

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final index = _tabs.indexOf(st.page);
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
            Expanded(child: animatedPage(context, st.page)),
          ],
        ),
        // Seven tabs: keep labels on one line even with large text. Icons and page titles still grow.
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.0,
          child: NavigationBar(
            selectedIndex: index < 0 ? 0 : index,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => st.goTo(_tabs[i]),
            destinations: [
              for (final p in _tabs)
                NavigationDestination(icon: Icon(pageIcon(p), size: 22), label: st.t(p.tab).length > 9 ? st.t(p.tab).substring(0, 9) : st.t(p.tab)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web: administrators get a side menu with the admin pages, on the same database.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final items = AppPage.values.where((p) => p.onWeb && st.canSee(p)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final index = items.indexOf(st.page);
    final pending = st.dash['pending_payments'];
    Widget icon(AppPage p) => p == AppPage.approvals && pending is int && pending > 0 ? Badge(label: Text('$pending'), child: Icon(pageIcon(p))) : Icon(pageIcon(p));

    return Scaffold(
      drawer: wide
          ? null
          : Builder(
              builder: (ctx) => NavigationDrawer(
                selectedIndex: index < 0 ? 0 : index,
                onDestinationSelected: (i) {
                  st.goTo(items[i]);
                  Navigator.of(ctx).maybePop();
                },
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('SACCO Ledger Admin', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final p in items) NavigationDrawerDestination(icon: icon(p), label: Text(st.t(p.title))),
                ],
              ),
            ),
      appBar: const TopBar(),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 220,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 1,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final p in items)
                      ListTile(
                        dense: true,
                        selected: p == st.page,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                        leading: icon(p),
                        title: Text(st.t(p.title)),
                        onTap: () => st.goTo(p),
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
