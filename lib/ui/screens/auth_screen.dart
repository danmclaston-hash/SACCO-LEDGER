import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/api.dart';
import '../theme.dart';
import '../widgets.dart';

const dataNotice = 'SACCO Ledger keeps records of your group\'s transactions: your name, phone, and what you paid or borrowed. '
    'Your group officers can see them. We never hold your money. Records are kept so your group can prove what happened. '
    'They are stored on secure cloud servers that may be outside Uganda, and by ticking you agree to this. '
    'You can ask your group to show or correct your records.';

/// Sign in, create account, or reset a password with a code from the secretary.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { signIn, signUp, reset }

class _AuthScreenState extends State<AuthScreen> {
  _Mode mode = _Mode.signIn;
  final id = TextEditingController();
  final pass = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  bool hide = true;

  Future<void> submit() async {
    final st = StateScope.of(context);
    if (!Phones.looksValid(id.text)) {
      showMsg(context, 'Enter a valid phone like 0772 123456, or an email.', error: true);
      return;
    }
    if (pass.text.length < 6) {
      showMsg(context, 'Password must have at least 6 characters.', error: true);
      return;
    }
    setState(() => busy = true);
    final email = Phones.loginEmail(id.text);
    try {
      switch (mode) {
        case _Mode.signIn:
          await st.api.signIn(email, pass.text);
          await st.loadOrgs();
        case _Mode.signUp:
          await st.api.signUp(email, pass.text);
          await st.loadOrgs();
        case _Mode.reset:
          final ok = await st.api.resetPassword(email, code.text, pass.text);
          if (!mounted) return;
          if (ok) {
            showMsg(context, 'Password changed. Sign in now.');
            setState(() => mode = _Mode.signIn);
          } else {
            showMsg(context, 'That code is not right. After 5 tries it stops working.', error: true);
          }
      }
    } on ApiError catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: cs.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.account_balance, size: 56, color: cs.secondary),
                const SizedBox(height: 8),
                Text(StateScope.of(context).t('app_title'), style: tt.headlineSmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold)),
                Text(kIsWeb ? 'Administrator portal' : 'Every shilling, on the record', style: tt.bodyMedium?.copyWith(color: saccoGoldLight)),
                const SizedBox(height: 20),
                SaccoCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(switch (mode) { _Mode.signIn => 'Sign in', _Mode.signUp => 'Create account', _Mode.reset => 'Forgot password' },
                        style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    gap,
                    TextField(controller: id, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Phone or email')),
                    gap,
                    if (mode == _Mode.reset) ...[
                      TextField(
                          controller: code,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Code from your group secretary')),
                      gap,
                    ],
                    TextField(
                      controller: pass,
                      obscureText: hide,
                      decoration: InputDecoration(
                        labelText: mode == _Mode.reset ? 'New password' : 'Password',
                        suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)),
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                    gap,
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(switch (mode) { _Mode.signIn => 'Sign in', _Mode.signUp => 'Create account', _Mode.reset => 'Change password' }),
                    ),
                    const SizedBox(height: 8),
                    if (mode != _Mode.signIn) TextButton(onPressed: () => setState(() => mode = _Mode.signIn), child: const Text('Back to sign in')),
                    if (mode == _Mode.signIn) ...[
                      TextButton(onPressed: () => setState(() => mode = _Mode.signUp), child: const Text('New here? Create account')),
                      TextButton(onPressed: () => setState(() => mode = _Mode.reset), child: const Text('Forgot password?')),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                Text('We never hold your money. We keep the records.', textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.onPrimary)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when signed in but not in any group yet.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final code = TextEditingController();
  bool agree = false;
  bool busy = false;

  Future<void> run(Future<String?> Function() fn) async {
    if (!agree) {
      showMsg(context, 'Please tick the data notice first.', error: true);
      return;
    }
    setState(() => busy = true);
    final st = StateScope.of(context);
    try {
      final select = await fn();
      await st.loadOrgs(select: select);
    } on ApiError catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void createGroup() {
    final st = StateScope.of(context);
    final name = TextEditingController();
    final me = TextEditingController();
    final phone = TextEditingController();
    final share = TextEditingController(text: '5000');
    var edition = 'tier_1_vsla';
    var currency = 'UGX';
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Create your group',
        confirm: 'Create',
        fields: (ctx, set) => [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')),
          TextField(controller: me, decoration: const InputDecoration(labelText: 'Your full name')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your phone')),
          DropdownButtonFormField<String>(
            initialValue: edition,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type of group'),
            items: [for (final e in editionNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => set(() => edition = v ?? edition),
          ),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final c in const ['UGX', 'KES', 'TZS', 'RWF']) DropdownMenuItem(value: c, child: Text(c))
            ],
            onChanged: (v) => set(() => currency = v ?? currency),
          ),
          TextField(controller: share, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price of one share')),
        ],
        onConfirm: (ctx) async {
          final nav = Navigator.of(ctx);
          final price = Money.parse(share.text, currency);
          if (name.text.trim().length < 2 || me.text.trim().length < 2 || price == null) {
            showMsg(ctx, 'Fill in group name, your name and share price.', error: true);
            return;
          }
          try {
            final id = await st.api.createOrganization(
                name: name.text.trim(),
                edition: edition,
                currency: currency,
                sharePrice: price,
                multiplier: 3,
                interest: 10,
                quorum: 67,
                myName: me.text.trim(),
                myPhone: phone.text);
            await st.loadOrgs(select: id);
            nav.pop();
          } on ApiError catch (e) {
            if (ctx.mounted) showMsg(ctx, e.message, error: true);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, title: const Text('Welcome'), actions: [
        IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: st.signOut),
      ]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SaccoCard(
                color: cs.secondaryContainer,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: agree,
                  onChanged: (v) => setState(() => agree = v ?? false),
                  title: const Text('Data notice', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(dataNotice),
                ),
              ),
              const SizedBox(height: 16),
              SaccoCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Join my group', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Text('Your secretary gives you an 8-letter code.'),
                  gap,
                  TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Invite code')),
                  gap,
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                              await st.api.claimInvite(code.text);
                              return null;
                            }),
                    child: const Text('Join'),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              SaccoCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Start a new group', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  gap,
                  FilledButton.tonal(
                    onPressed: busy
                        ? null
                        : () {
                            if (!agree) {
                              showMsg(context, 'Please tick the data notice first.', error: true);
                            } else {
                              createGroup();
                            }
                          },
                    child: const Text('Create group'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: busy ? null : () => run(() => st.api.seedDemo('Me (demo admin)')), child: const Text('Try with demo data')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A plain member opened the web address. The web is for administrators only.
class MembersUseAppScreen extends StatelessWidget {
  const MembersUseAppScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phone_android, size: 56, color: Theme.of(context).colorScheme.primary),
            gap,
            const Text('This website is for group administrators.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Members use the SACCO Ledger app on Android or iPhone.', textAlign: TextAlign.center),
            gap,
            OutlinedButton(onPressed: st.signOut, child: const Text('Sign out')),
          ]),
        ),
      ),
    );
  }
}

/// The app was built without its keys. Explains what to do instead of crashing.
class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'App needs its database keys.\n\nBuild with:\n--dart-define=SUPABASE_URL=...\n--dart-define=SUPABASE_KEY=...\n\nSee README, step 3.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
