import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'data/api.dart';
import 'state/app_state.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/shells.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(MaterialApp(theme: lightTheme, home: const NotConfiguredScreen()));
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  final state = AppState(Api());
  runApp(SaccoApp(state: state));
  await state.boot();
}

class SaccoApp extends StatelessWidget {
  final AppState state;
  const SaccoApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) => StateScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MaterialApp(
            title: 'SACCO Ledger',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: state.themeMode,
            // The person's text size, on top of the phone's own setting, capped so layouts hold.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final scale = (mq.textScaler.scale(16) / 16 * state.textScale).clamp(0.85, 2.0);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              );
            },
            home: const _LifecycleGate(child: _Root()),
          ),
        ),
      );
}

/// Tells the app state when the app goes to the background and comes back, for the PIN lock.
class _LifecycleGate extends StatefulWidget {
  final Widget child;
  const _LifecycleGate({required this.child});
  @override
  State<_LifecycleGate> createState() => _LifecycleGateState();
}

class _LifecycleGateState extends State<_LifecycleGate> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onHide: () => StateScope.of(context).appHidden(), onShow: () => StateScope.of(context).appShown());
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    if (st.booting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!st.signedIn) return const AuthScreen();
    if (st.locked) return const LockScreen();
    if (st.org == null) return const OnboardingScreen();
    // FORCE_MOBILE lets a developer see the phone layout in Chrome. Real web builds never set it.
    const forceMobile = bool.fromEnvironment('FORCE_MOBILE');
    if (kIsWeb && !forceMobile) {
      // The web address is the admin portal. Members use the phone app.
      final anyOfficer = st.orgs.any((o) => o['my_role'] != 'member');
      if (!anyOfficer) return const MembersUseAppScreen();
      return const AdminShell();
    }
    return const MobileShell();
  }
}
