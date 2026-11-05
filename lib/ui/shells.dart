import 'package:flutter/material.dart';

import '../core/search_index.dart';
import '../state/app_state.dart';
import 'screens/approvals_screen.dart';
import 'screens/channels_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/emergency_screen.dart';
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

Widget pageBody(AppPage p) => switch (p) {
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

/// Phones: the same bottom bar as the original app.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  static const _items = [
    (AppPage.overview, 'dashboard', Icons.dashboard),
    (AppPage.meetings, 'meetings', Icons.groups),
    (AppPage.loans, 'loans', Icons.request_quote),
    (AppPage.emergency, 'emergency', Icons.health_and_safety),
    (AppPage.ledger, 'ledger', Icons.account_balance_wallet),
    (AppPage.shareOut, 'share_out', Icons.calculate),
    (AppPage.channels, 'Channels', Icons.phone_iphone),
  ];

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final index = _items.indexWhere((e) => e.$1 == st.page);
    return PopScope(
      canPop: st.page == AppPage.overview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) st.goTo(AppPage.overview);
      },
      child: Scaffold(
        appBar: const TopBar(),
        body: Column(children: [
          if (st.loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: pageBody(st.page)),
        ]),
        bottomNavigationBar: NavigationBar(
          // Pages reached from Overview (members, approvals...) keep Overview lit.
          selectedIndex: index < 0 ? 0 : index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => st.goTo(_items[i].$1),
          destinations: [
            for (final e in _items)
              NavigationDestination(
                icon: Icon(e.$3, size: 22),
                label: st.t(e.$2).length > 9 ? st.t(e.$2).substring(0, 9) : st.t(e.$2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Web: administrators get a side menu with the admin pages, on the same database.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  List<(AppPage, String, IconData)> _items(AppState st) => [
        (AppPage.overview, st.t('dashboard'), Icons.dashboard),
        (AppPage.approvals, 'Approvals', Icons.fact_check),
        (AppPage.members, st.t('members'), Icons.people),
        (AppPage.meetings, st.t('meetings'), Icons.groups),
        (AppPage.loans, st.t('loans'), Icons.request_quote),
        (AppPage.emergency, st.t('emergency'), Icons.health_and_safety),
        (AppPage.ledger, 'Ledger & Audit', Icons.account_balance_wallet),
        (AppPage.statements, 'Statements', Icons.receipt_long),
        (AppPage.shareOut, st.t('share_out'), Icons.calculate),
        (AppPage.licences, 'Licences', Icons.verified),
        (AppPage.settings, 'Settings', Icons.settings),
        if (st.orgs.any((o) => o['my_role'] == 'platform_admin') || st.isPlatformAdmin) (AppPage.platform, 'All groups', Icons.domain),
      ];

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final items = _items(st);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final index = items.indexWhere((e) => e.$1 == st.page);
    final pending = st.dash['pending_payments'];
    Widget icon((AppPage, String, IconData) e) =>
        e.$1 == AppPage.approvals && pending is int && pending > 0 ? Badge(label: Text('$pending'), child: Icon(e.$3)) : Icon(e.$3);

    return Scaffold(
      drawer: wide
          ? null
          : Builder(
              builder: (ctx) => NavigationDrawer(
                selectedIndex: index < 0 ? 0 : index,
                onDestinationSelected: (i) {
                  st.goTo(items[i].$1);
                  Navigator.of(ctx).maybePop();
                },
                children: [
                  const Padding(padding: EdgeInsets.all(20), child: Text('SACCO Ledger Admin', style: TextStyle(fontWeight: FontWeight.bold))),
                  for (final e in items) NavigationDrawerDestination(icon: icon(e), label: Text(e.$2)),
                ],
              ),
            ),
      appBar: const TopBar(),
      body: Row(children: [
        if (wide)
          SizedBox(
            width: 220,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 1,
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
                for (final (i, e) in items.indexed)
                  ListTile(
                    dense: true,
                    selected: i == index,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    leading: icon(e),
                    title: Text(e.$2),
                    onTap: () => st.goTo(e.$1),
                  ),
              ]),
            ),
          ),
        Expanded(
          child: Column(children: [
            if (st.loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: pageBody(st.page)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
