import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'data/api.dart';
import 'state/app_state.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/circles_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/two_step.dart';
import 'ui/shells.dart';
import 'ui/tour.dart';
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
            theme: themeFor(state.look, Brightness.light),
            darkTheme: themeFor(state.look, Brightness.dark),
            themeMode: state.themeMode,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final scale = (mq.textScaler.scale(16) / 16 * state.textScale).clamp(0.85, 2.0);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              );
            },
            home: const _LifecycleGate(child: JoinLinkGate(child: _Root())),
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
    if (st.twoStepCodeNeeded) return const TwoStepCodeScreen();
    if (st.recovering) return const NewPasswordScreen();
    if (st.locked) return const LockScreen();
    if (st.org == null) return const OnboardingScreen();
    // One app for everyone. A wide browser window gets the side menu; phones and narrow windows get the phone layout.
    // What a person can open depends on their role, never on the device. FORCE_MOBILE shows the phone layout in Chrome.
    const forceMobile = bool.fromEnvironment('FORCE_MOBILE');
    final wide = kIsWeb && !forceMobile && MediaQuery.sizeOf(context).width >= 840;
    return TourGate(child: wide ? const WideShell() : const MobileShell());
  }
}
