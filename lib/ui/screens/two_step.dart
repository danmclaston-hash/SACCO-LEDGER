import 'package:flutter/material.dart' hide Text, InputDecoration;
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Factor;
import 'package:url_launcher/url_launcher.dart';

import '../../core/json.dart';
import '../../core/pages.dart';
import '../../data/api.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text.dart';

/// A QR code drawn square by square, so no picture is downloaded from anywhere.
class QrPicture extends StatelessWidget {
  final String data;
  final double size;
  const QrPicture(this.data, {super.key, this.size = 200});

  @override
  Widget build(BuildContext context) {
    final img = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    return Semantics(
      label: 'QR code for your authenticator app',
      child: Container(
        color: Colors.white, // scanners need dark on light, in dark mode too
        padding: const EdgeInsets.all(12),
        child: CustomPaint(size: Size.square(size), painter: _QrPainter(img)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage img;
  _QrPainter(this.img);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / img.moduleCount;
    final p = Paint()..color = Colors.black;
    for (var r = 0; r < img.moduleCount; r++) {
      for (var c = 0; c < img.moduleCount; c++) {
        if (img.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.5, cell + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.img != img;
}

/// One row in My Account → Security: is two-step sign-in on, and a switch.
class TwoStepTile extends StatefulWidget {
  const TwoStepTile({super.key});
  @override
  State<TwoStepTile> createState() => _TwoStepTileState();
}

class _TwoStepTileState extends State<TwoStepTile> {
  Future<Factor?>? _factor;

  void _reload() => setState(() => _factor = StateScope.of(context).api.twoStepFactor());

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    _factor ??= st.api.twoStepFactor();
    return FutureBuilder<Factor?>(
      future: _factor,
      builder: (context, snap) {
        final on = snap.data != null;
        final needed = st.platform.b('team');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minTileHeight: 56,
          leading: Icon(Icons.verified_user_outlined, color: on ? SaccoLook.of(context).ok : null),
          title: const Text('Two-step sign-in'),
          subtitle: Text(on
              ? 'On. After your password, the app asks for a code from your authenticator app.'
              : needed
                  ? 'Needed for platform tools. Protects your account even if someone learns your password.'
                  : 'Off. Recommended for admins and treasurers: a stolen password alone will not open your account.'),
          trailing: snap.connectionState != ConnectionState.done
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Switch(
                  value: on,
                  onChanged: (v) async {
                    if (v) {
                      if (await showTwoStepSetup(context) && mounted) _reload();
                    } else {
                      await _turnOff(context, snap.data!);
                      if (mounted) _reload();
                    }
                  },
                ),
        );
      },
    );
  }

  Future<void> _turnOff(BuildContext context, Factor f) async {
    final st = StateScope.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off two-step sign-in?'),
        content: Text(st.platform.b('team')
            ? 'Your platform tools will stop working until you turn it on again.'
            : 'Anyone who learns your password could then open your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it on')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    try {
      await st.api.stopTwoStep(f.id);
      await st.refresh();
      if (context.mounted) showMsg(context, 'Two-step sign-in is off.');
    } on ApiError catch (e) {
      if (context.mounted) showMsg(context, e.message, error: true);
    }
  }
}

/// Setting up: scan the QR code (or type the key) in an authenticator app, then type the 6 numbers it shows.
/// Returns true when it is on.
Future<bool> showTwoStepSetup(BuildContext context) async {
  final st = StateScope.of(context);
  final ({String id, String secret, String uri}) start;
  try {
    start = await st.api.startTwoStep();
  } on ApiError catch (e) {
    if (context.mounted) showMsg(context, e.message, error: true);
    return false;
  }
  if (!context.mounted) return false;
  final code = TextEditingController();
  var done = false;
  await showDialog(
    context: context,
    builder: (_) => FormDialog(
      title: 'Turn on two-step sign-in',
      confirm: 'Turn on',
      fields: (ctx, set) => [
        const Text('1. Install an authenticator app on your phone: Google Authenticator or Microsoft Authenticator. Both are free.'),
        const Text('2. In the app, tap + and scan this code.'),
        Center(child: QrPicture(start.uri, size: 180)),
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(start.uri)),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('On this phone? Open the app instead'),
        ),
        Text('Can\'t scan? Type this key in the app:', style: Theme.of(ctx).textTheme.bodySmall),
        Row(children: [
          Expanded(
            child: SelectableText(start.secret,
                style: SaccoLook.of(ctx).numbers(Theme.of(ctx).textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          IconButton(
            tooltip: tr('Copy key'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: start.secret)),
          ),
        ]),
        const Text('3. Type the 6 numbers the app shows now.'),
        TextField(
          controller: code,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(labelText: '6-number code'),
        ),
      ],
      onConfirm: (ctx) async {
        if (code.text.trim().length != 6) {
          showMsg(ctx, 'Type the 6 numbers from the app.', error: true);
          return;
        }
        final nav = Navigator.of(ctx);
        try {
          await st.api.checkTwoStepCode(start.id, code.text);
          done = true;
          nav.pop();
        } on ApiError catch (e) {
          if (ctx.mounted) showMsg(ctx, e.message, error: true);
        }
      },
    ),
  );
  if (done) {
    await st.twoStepDone();
    if (context.mounted) showMsg(context, 'Two-step sign-in is on. Keep your authenticator app: you need it to sign in.');
  }
  return done;
}

/// After the password, when two-step sign-in is on: the 6-number code from the authenticator app.
class TwoStepCodeScreen extends StatefulWidget {
  const TwoStepCodeScreen({super.key});
  @override
  State<TwoStepCodeScreen> createState() => _TwoStepCodeScreenState();
}

class _TwoStepCodeScreenState extends State<TwoStepCodeScreen> {
  final code = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> _check() async {
    final st = StateScope.of(context);
    if (code.text.trim().length != 6) {
      setState(() => error = 'Type the 6 numbers from your authenticator app.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final f = await st.api.twoStepFactor();
      if (f == null) {
        await st.twoStepDone();
        return;
      }
      await st.api.checkTwoStepCode(f.id, code.text);
      await st.twoStepDone();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
          code.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final look = SaccoLook.of(context);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: look.brand,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: RiseIn(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.verified_user_rounded, size: 56, color: look.accent),
                  const SizedBox(height: 12),
                  Text('One more step', textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(color: look.onBrand, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Open your authenticator app and type the 6 numbers for SACCO Ledger.',
                      textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: look.onBrandMuted)),
                  const SizedBox(height: 20),
                  SaccoCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: code,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        style: look.numbers(tt.headlineSmall).copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(labelText: '6-number code'),
                        onSubmitted: (_) => _check(),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                        ),
                      gap,
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: busy ? null : _check,
                        child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Continue'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: look.onBrand),
                    onPressed: st.signOut,
                    child: const Text('Use a different account'),
                  ),
                  Text('Lost your phone with the authenticator app? Contact the SACCO Ledger team to prove who you are.',
                      textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// For the platform team before two-step sign-in is on: why the tools are missing, and one button to fix it.
class TwoStepNeededCard extends StatelessWidget {
  const TwoStepNeededCard({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    if (!st.platformNeedsTwoStep) return const SizedBox.shrink();
    final look = SaccoLook.of(context);
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: look.accent, borderRadius: BorderRadius.circular(look.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield_rounded, color: look.onAccent),
          const SizedBox(width: 8),
          Expanded(child: Text('Turn on two-step sign-in', style: tt.titleMedium?.copyWith(color: look.onAccent, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(
          'You are on the platform team. Your tools (all groups, the people list, invitations) stay locked until two-step sign-in is on. '
          'This way a stolen password can never open the whole platform.',
          style: tt.bodyMedium?.copyWith(color: look.onAccent),
        ),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: look.brand, foregroundColor: look.onBrand),
          onPressed: () => showTwoStepSetup(context),
          child: const Text('Turn it on now'),
        ),
      ]),
    );
  }
}

/// After the "reset your password" email link: choose a new password.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final a = TextEditingController();
  final b = TextEditingController();
  bool busy = false;
  bool hide = true;
  String? error;

  Future<void> _save() async {
    final st = StateScope.of(context);
    if (a.text.length < 6) return setState(() => error = 'At least 6 characters.');
    if (a.text != b.text) return setState(() => error = 'The two passwords are different.');
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await st.api.setNewPassword(a.text);
      await st.passwordChosen();
      if (mounted) showMsg(context, 'Password changed. You are signed in.');
      st.goTo(AppPage.overview);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = SaccoLook.of(context);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: look.brand,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.lock_reset_rounded, size: 56, color: look.accent),
                const SizedBox(height: 12),
                Text('Choose a new password', textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(color: look.onBrand, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                SaccoCard(
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: a,
                        obscureText: hide,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'New password',
                          helperText: 'At least 6 characters',
                          suffixIcon: IconButton(
                            tooltip: hide ? 'Show password' : 'Hide password',
                            icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => hide = !hide),
                          ),
                        ),
                      ),
                      gap,
                      TextField(
                        controller: b,
                        obscureText: hide,
                        decoration: InputDecoration(labelText: 'Same password again'),
                        onSubmitted: (_) => _save(),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
                        ),
                      gap,
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: busy ? null : _save,
                        child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save password'),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
