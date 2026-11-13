import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/data/api.dart';
import 'package:sacco_ledger/state/app_state.dart';
import 'package:sacco_ledger/core/pages.dart';
import 'package:sacco_ledger/ui/screens/auth_screen.dart';
import 'package:sacco_ledger/ui/screens/channels_screen.dart';
import 'package:sacco_ledger/ui/screens/circles_screen.dart';
import 'package:sacco_ledger/ui/screens/two_step.dart';
import 'package:sacco_ledger/ui/screens/loan_calculator.dart';
import 'package:sacco_ledger/ui/shells.dart';
import 'package:sacco_ledger/ui/theme.dart';
import 'package:sacco_ledger/core/i18n.dart';
import 'package:sacco_ledger/ui/tour.dart';
import 'package:sacco_ledger/ui/widgets.dart';

/// Opens the new screens on a small phone and fails on any overflow or crash.
Widget app(AppState st, Widget child, {ThemeMode mode = ThemeMode.light}) => StateScope(
      state: st,
      child: MaterialApp(theme: lightTheme, darkTheme: darkTheme, themeMode: mode, home: child),
    );

void main() {
  // The language is app-wide; each test starts in English.
  setUp(() => Lang.current = AppLanguage.en);
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

  testWidgets('tour: points at parts, skips missing ones, next, back, later', (t) async {
    await phone(t);
    final st = AppState(Api());
    await t.pumpWidget(app(
        st,
        Builder(
            builder: (c) => Scaffold(
                  body: Column(children: [
                    TourTarget.money.wrap(const SizedBox(height: 120, width: 300, child: Text('money box'))),
                    TextButton(onPressed: () => showTour(c), child: const Text('go')),
                  ]),
                ))));
    await t.tap(find.text('go'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 1200));
    // Only the welcome, the one part on screen, and the finish remain: 3 steps.
    expect(find.text('1/3'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pump(const Duration(milliseconds: 1200));
    expect(find.text('Your money, one look'), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pump(const Duration(milliseconds: 1200));
    expect(find.text('Welcome to SACCO Ledger'), findsOneWidget);
    await t.tap(find.text('Later'));
    await t.pump(const Duration(milliseconds: 100));
    expect(st.tourLater, isTrue);
    expect(st.tourDone, isFalse);
    expect(find.text('Welcome to SACCO Ledger'), findsNothing);
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
    await t.pumpWidget(
        app(st, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showPaymentDialog(c, online: online), child: const Text('go'))))));
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
    // Four tabs and More. A member gets Pay; officer pages are not offered.
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Pay'), findsWidgets);
    expect(find.text('Approvals'), findsNothing);
    await t.tap(find.text('More'));
    await t.pumpAndSettle();
    expect(find.text('Statements'), findsOneWidget);
    for (final p in [AppPage.members, AppPage.ledger, AppPage.settings, AppPage.licences, AppPage.platform]) {
      expect(find.text(p.tab), findsNothing);
    }
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await t.pumpWidget(app(inGroup('treasurer'), const MobileShell()));
    await t.pumpAndSettle();
    expect(find.text('Approvals'), findsWidgets);

    // A tall desktop window, so the whole grouped side menu is on screen.
    t.view.physicalSize = const Size(1280 * 3, 1400 * 3);
    final admin = inGroup('treasurer');
    await t.pumpWidget(app(admin, const WideShell()));
    await t.pumpAndSettle();
    for (final p in [AppPage.approvals, AppPage.members, AppPage.settings]) {
      expect(find.text(p.title), findsWidgets);
    }
    expect(find.text(AppPage.platform.title), findsNothing);
  });

  testWidgets('extra data loads once per reload, not on every redraw', (t) async {
    final st = inGroup('member');
    var calls = 0;
    await t.pumpWidget(app(st, Scaffold(body: Loaded<int>(load: () async => ++calls, builder: (_, n) => Text('load $n')))));
    await t.pumpAndSettle();
    st.goTo(AppPage.overview); // redraws everything that watches the app state
    await t.pumpAndSettle();
    expect(calls, 1);
    st.version++; // what every reload does
    st.goTo(AppPage.overview);
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('load 2'), findsOneWidget);
  });

  testWidgets('My circles: grouped by role, invitation opens with my details filled in, both themes', (t) async {
    // A phone's width, tall enough to see the whole page at once.
    t.view.physicalSize = const Size(360 * 3, 2200 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final st = AppState(Api());
    Map<String, dynamic> circle(String id, String name, String role) =>
        {'id': id, 'name': name, 'my_role': role, 'people': 12, 'currency_code': 'UGX', 'edition': 'tier_1_vsla', 'is_demo': false};
    st.orgs = [
      circle('a', 'Twekembe Women Savers', 'member'),
      circle('b', 'Kampala Boda Riders Circle', 'org_admin'),
      circle('c', 'Church Welfare Group', 'treasurer'),
      circle('d', 'Someone Else Circle', 'platform_admin'),
    ];
    st.org = st.orgs[1];
    st.account = {'full_name': 'Okecho Laston', 'phone': '256700000001'};
    st.invites = [
      {
        'code': 'ABCD2345',
        'org_id': 'e',
        'org_name': 'Mbale Farmers Circle',
        'role': 'secretary',
        'invited_by': 'Ann Namubiru',
        'message': 'We meet on Saturdays at 10.',
        'people': 18,
        'currency_code': 'UGX',
        'edition': 'tier_2_sacco',
        'country_code': 'UG',
        'admin_name': 'Ann Namubiru',
        'expires_at': '2026-11-27T10:00:00Z',
      },
    ];
    for (final m in [ThemeMode.light, ThemeMode.dark]) {
      await t.pumpWidget(app(st, const Scaffold(body: CirclesScreen()), mode: m));
      await t.pumpAndSettle();
      expect(find.text('I lead (1)'), findsOneWidget);
      expect(find.text('I help run (1)'), findsOneWidget);
      expect(find.text('I am a member (1)'), findsOneWidget);
      expect(find.text('Someone Else Circle'), findsNothing); // look-only circles are not "mine"
      expect(find.text('OPEN NOW'), findsOneWidget);
      expect(find.text('YOU ARE INVITED'), findsOneWidget);
      expect(t.takeException(), isNull);
    }
    await t.tap(find.text('See and join'));
    await t.pumpAndSettle();
    expect(find.text('Mbale Farmers Circle'), findsWidgets);
    expect(find.textContaining('another circle inside SACCO Ledger'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Okecho Laston'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Join Mbale Farmers Circle'), 200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('Join Mbale Farmers Circle'));
    await t.pumpAndSettle();
    expect(find.text('Please tick the data notice first.'), findsOneWidget); // nobody joins without saying yes to the notice
    expect(t.takeException(), isNull);
  });

  testWidgets('two-step sign-in screens: code, new password, QR and the platform warning, both themes', (t) async {
    await phone(t);
    final st = AppState(Api());
    st.platform = {'team': true, 'role': 'owner', 'two_step': false};
    for (final m in [ThemeMode.light, ThemeMode.dark]) {
      await t.pumpWidget(app(st, const TwoStepCodeScreen(), mode: m));
      await t.pumpAndSettle();
      expect(find.text('One more step'), findsOneWidget);
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.textContaining('6 numbers'), findsWidgets); // asks for the code, never lets an empty one through

      await t.pumpWidget(app(st, const NewPasswordScreen(), mode: m));
      await t.enterText(find.byType(TextField).first, 'abcdef');
      await t.enterText(find.byType(TextField).last, 'abcdeg');
      await t.tap(find.text('Save password'));
      await t.pumpAndSettle();
      expect(find.text('The two passwords are different.'), findsOneWidget);

      await t.pumpWidget(app(
          st,
          const Scaffold(
              body: Column(children: [TwoStepNeededCard(), QrPicture('otpauth://totp/SACCO%20Ledger:x?secret=ABC&issuer=SACCO%20Ledger', size: 120)])),
          mode: m));
      await t.pumpAndSettle();
      expect(find.text('Turn on two-step sign-in'), findsOneWidget);
      expect(t.takeException(), isNull);
    }
    st.platform = {'team': true, 'two_step': true};
    await t.pumpWidget(app(st, const Scaffold(body: TwoStepNeededCard())));
    expect(find.text('Turn on two-step sign-in'), findsNothing); // gone once it is on
  });
}
