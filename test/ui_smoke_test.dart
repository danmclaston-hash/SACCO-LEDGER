import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/data/api.dart';
import 'package:sacco_ledger/state/app_state.dart';
import 'package:sacco_ledger/core/pages.dart';
import 'package:sacco_ledger/ui/screens/auth_screen.dart';
import 'package:sacco_ledger/ui/screens/channels_screen.dart';
import 'package:sacco_ledger/ui/screens/loan_calculator.dart';
import 'package:sacco_ledger/ui/shells.dart';
import 'package:sacco_ledger/ui/theme.dart';
import 'package:sacco_ledger/ui/tour.dart';
import 'package:sacco_ledger/ui/widgets.dart';

/// Opens the new screens on a small phone and fails on any overflow or crash.
Widget app(AppState st, Widget child, {ThemeMode mode = ThemeMode.light}) => StateScope(
      state: st,
      child: MaterialApp(theme: lightTheme, darkTheme: darkTheme, themeMode: mode, home: child),
    );

void main() {
  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(360 * 3, 740 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('sign-up shows country and language', (t) async {
    await phone(t);
    final st = AppState(Api());
    await t.pumpWidget(app(st, const AuthScreen()));
    await t.tap(find.text('New here? Create account'));
    await t.pumpAndSettle();
    expect(find.text('Country'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Kenya').last);
    await t.pumpAndSettle();
    expect(st.country, 'KE');
    expect(find.textContaining('+254'), findsWidgets);
  });

  testWidgets('welcome tour: next, back, later', (t) async {
    await phone(t);
    final st = AppState(Api());
    await t.pumpWidget(app(st, Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showTour(c), child: const Text('go')))))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('1 of 5'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.text('Start'), findsOneWidget);
    await t.tap(find.text('Later'));
    await t.pumpAndSettle();
    expect(st.tourLater, isTrue);
    expect(st.tourDone, isFalse);
  });

  testWidgets('info button explains a word, and hides when switched off', (t) async {
    await phone(t);
    final st = AppState(Api());
    await t.pumpWidget(app(st, const Scaffold(body: SectionTitle('Share-out', info: 'share_out'))));
    await t.tap(find.byIcon(Icons.info_outline));
    await t.pumpAndSettle();
    expect(find.textContaining('end of a cycle'), findsOneWidget);
    await t.tapAt(const Offset(20, 20)); // close the explanation
    await t.pumpAndSettle();
    await st.updateSettings(showTips: false);
    await t.pumpWidget(app(st, const Scaffold(body: SectionTitle('Ledger', info: 'ledger'))));
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('brand buttons in both themes', (t) async {
    await phone(t);
    final st = AppState(Api());
    for (final m in [ThemeMode.light, ThemeMode.dark]) {
      await t.pumpWidget(app(
          st,
          Scaffold(
            body: Column(children: [
              Row(children: [
                Expanded(child: BrandButton(channel: 'mtn_momo', label: 'MTN *165#', onPressed: () {})),
                const SizedBox(width: 8),
                Expanded(child: BrandButton(channel: 'airtel_money', label: 'Airtel *185#', onPressed: () {})),
              ]),
              for (final c in brands.keys) BrandChip(c),
            ]),
          ),
          mode: m));
      await t.pumpAndSettle();
      expect(find.text('MTN *165#'), findsOneWidget);
    }
  });

  testWidgets('loan calculator: group rules, then other rules, then lateness', (t) async {
    await phone(t);
    final st = AppState(Api());
    st.org = {
      'id': 'g1',
      'currency_code': 'UGX',
      'role': 'member',
      'loan_interest_mode': 'monthly',
      'loan_interest_rate': 5,
      'loan_calculation': 'flat',
      'loan_free_months': 1,
      'loan_repayment_plan': 'monthly',
      'late_fee_type': 'percent',
      'late_fee_pct': 10,
      'late_fee_every': 'week',
      'late_fee_grace_days': 3,
    };
    await t.pumpWidget(app(st, const LoanCalculatorScreen()));
    await t.enterText(find.byType(TextField).first, '12000');
    await t.pumpAndSettle();
    expect(find.text('UGX 13,200'), findsOneWidget); // 12000 + 2 months of 5%
    expect(find.textContaining('Month 2'), findsOneWidget); // first month free
    await t.scrollUntilVisible(find.textContaining('Late fee:'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Late fee: UGX 400'), findsOneWidget); // 10 days late, 3 grace days: 1 week of 10% of 4000
    await t.scrollUntilVisible(find.text('Try other loan rules'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Try other loan rules'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('No interest'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('No interest'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Pay back in total'), -300, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text('UGX 12,000'), findsWidgets);
  });

  AppState inGroup(String role) => AppState(Api())
    ..org = {'id': 'g1', 'name': 'Test Group', 'currency_code': 'UGX', 'my_role': role, 'my_member_id': 'm1', 'share_price': 5000, 'edition': 'tier_1_vsla'};

  Future<void> openPayment(WidgetTester t, AppState st, {bool online = false}) async {
    await t.pumpWidget(app(st, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showPaymentDialog(c, online: online), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  testWidgets('record a payment: cash needs no transaction ID', (t) async {
    await phone(t);
    await openPayment(t, inGroup('member'));
    expect(find.text('Record a Payment'), findsOneWidget);
    expect(find.text('Transaction ID from the SMS'), findsOneWidget);
    await t.tap(find.text('MTN MoMo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cash').last);
    await t.pumpAndSettle();
    expect(find.text('Transaction ID from the SMS'), findsNothing);
  });

  testWidgets('a member cannot record money leaving the group', (t) async {
    await phone(t);
    await openPayment(t, inGroup('member'));
    await t.tap(find.text('Buy shares'));
    await t.pumpAndSettle();
    expect(find.text('Loan repayment'), findsWidgets);
    expect(find.text('Savings withdrawal'), findsNothing);
  });

  testWidgets('pay online asks the same questions but no channel', (t) async {
    await phone(t);
    await openPayment(t, inGroup('treasurer'), online: true);
    expect(find.text('Pay online'), findsOneWidget);
    expect(find.text('Savings deposit'), findsOneWidget);
    expect(find.text('How the money moved'), findsNothing);
    expect(find.textContaining('secure payment page'), findsOneWidget);
  });

  testWidgets('phone tabs and admin menu come from the page list', (t) async {
    await phone(t);
    await t.pumpWidget(app(inGroup('member'), const MobileShell()));
    await t.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(7));
    expect(find.text('Channels'), findsOneWidget);

    t.view.physicalSize = const Size(1280 * 3, 900 * 3);
    final admin = inGroup('treasurer');
    await t.pumpWidget(app(admin, const AdminShell()));
    await t.pumpAndSettle();
    for (final p in [AppPage.approvals, AppPage.members, AppPage.settings]) {
      expect(find.text(p.title), findsWidgets);
    }
    expect(find.text(AppPage.channels.title), findsNothing);
    expect(find.text(AppPage.platform.title), findsNothing);
  });
}
