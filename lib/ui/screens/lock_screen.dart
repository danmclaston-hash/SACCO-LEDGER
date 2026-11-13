import 'package:flutter/material.dart' hide Text, InputDecoration;
import 'package:flutter/services.dart';

import '../../core/app_lock.dart';
import '../../core/json.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_screen.dart';
import '../text.dart';

/// Shown instead of the app when the PIN lock is on and the app was away too long.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '';
  String? message;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    final st = StateScope.of(context);
    if (st.useBiometrics) await st.unlockWithBiometrics();
  }

  Future<void> _press(String d) async {
    if (busy) return;
    HapticFeedback.selectionClick();
    if (d == '<') {
      if (pin.isNotEmpty) setState(() => pin = pin.substring(0, pin.length - 1));
      return;
    }
    if (pin.length >= PinLock.maxLength) return;
    setState(() {
      pin += d;
      message = null;
    });
  }

  Future<void> _submit() async {
    final st = StateScope.of(context);
    if (pin.length < PinLock.minLength) {
      setState(() => message = 'Type your 4 to 6 number PIN.');
      return;
    }
    setState(() => busy = true);
    final ok = await st.unlockWithPin(pin);
    if (!mounted) return;
    setState(() {
      busy = false;
      pin = '';
      if (!ok) {
        final left = maxPinTries - st.pinTries;
        message = st.signedIn ? 'Wrong PIN. $left tries left, then you must sign in again.' : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final a = st.account;
    final look = SaccoLook.of(context);
    return Scaffold(
      backgroundColor: look.brand,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                children: [
                  Avatar(name: a.s('full_name').isEmpty ? '?' : a.s('full_name'), photo: a['avatar'] as String?, size: 72),
                  const SizedBox(height: 12),
                  Text(
                    a.s('full_name').isEmpty ? 'Welcome back' : 'Hello, ${a.s('full_name').split(' ').first}',
                    style: tt.titleLarge?.copyWith(color: look.onBrand, fontWeight: FontWeight.bold),
                  ),
                  Text('Enter your app PIN', style: tt.bodyMedium?.copyWith(color: look.onBrandMuted)),
                  const SizedBox(height: 20),
                  Semantics(
                    label: '${pin.length} numbers typed',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < PinLock.maxLength; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < pin.length ? look.accent : Colors.transparent,
                              border: Border.all(color: i < PinLock.minLength ? Colors.white : Colors.white54, width: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: message == null
                          ? null
                          : Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: tt.bodySmall?.copyWith(color: const Color(0xFFFFB4AB), fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['bio', '0', '<'],
                  ])
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [for (final k in row) _Key(k, st.useBiometrics, onTap: k == 'bio' ? _tryBiometrics : () => _press(k))],
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: look.accent, foregroundColor: look.onAccent, minimumSize: const Size.fromHeight(52)),
                      onPressed: busy ? null : _submit,
                      child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Unlock'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: st.signOut,
                    child: const Text('Forgot PIN? Sign in with password'),
                  ),
                  Text('The PIN lives only on this phone.', style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String k;
  final bool bio;
  final VoidCallback onTap;
  const _Key(this.k, this.bio, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (k == 'bio' && !bio) return const SizedBox(width: 84, height: 84);
    final accent = SaccoLook.of(context).accent;
    final child = switch (k) {
      'bio' => Icon(Icons.fingerprint, color: accent, size: 34),
      '<' => const Icon(Icons.backspace_outlined, color: Colors.white),
      _ => Text(
          k,
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w500),
        ),
    };
    final key = Padding(
      padding: const EdgeInsets.all(6),
      child: Semantics(
        button: true,
        label: switch (k) {
          'bio' => 'Unlock with fingerprint or face',
          '<' => 'Delete last number',
          _ => k,
        },
        excludeSemantics: true,
        child: Material(
          color: Colors.white.withValues(alpha: 0.10),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 72, height: 72, child: Center(child: child)),
          ),
        ),
      ),
    );
    if (k != 'bio') return key;
    return SizedBox(width: 84, height: 84, child: OverflowBox(maxWidth: 108, maxHeight: 108, child: PulseRing(size: 72, color: accent, child: key)));
  }
}
