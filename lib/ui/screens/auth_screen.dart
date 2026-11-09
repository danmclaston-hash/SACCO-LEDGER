import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/catalog.dart';
import '../../core/countries.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../data/api.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_screen.dart';

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

  /// Set after sign-up (or a sign-in before the link was clicked): the email we are waiting on.
  String? waitingFor;

  Future<void> resend() async {
    final e = waitingFor;
    if (e == null) return;
    setState(() => busy = true);
    try {
      await StateScope.of(context).api.resendConfirmation(e);
      if (mounted) showMsg(context, 'Sent again to $e. It can take a minute. Check Spam too.');
    } on ApiError catch (err) {
      if (mounted) showMsg(context, err.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    final st = StateScope.of(context);
    final c = countryByCode(st.country);
    if (!Phones.looksValid(id.text, dial: c.dial)) {
      showMsg(context, 'Enter a valid phone like ${c.example}, or an email.', error: true);
      return;
    }
    final typed = id.text.trim().toLowerCase();
    if (mode == _Mode.signUp && !typed.contains('@')) {
      showMsg(context, 'New accounts with a phone number are paused until we can text you a code. Use your email or Google for now.', error: true);
      return;
    }
    final fix = emailTypo(typed);
    if (mode == _Mode.signUp && fix != null) {
      showMsg(context, 'Did you mean $fix? Fix the email and try again.', error: true);
      return;
    }
    if (pass.text.length < 6) {
      showMsg(context, 'Password must have at least 6 characters.', error: true);
      return;
    }
    setState(() => busy = true);
    final email = Phones.loginEmail(id.text, dial: c.dial);
    try {
      switch (mode) {
        case _Mode.signIn:
          // The sign-in event reloads everything (app_state.dart, boot), for password and Google alike.
          await st.api.signIn(email, pass.text);
          TextInput.finishAutofillContext();
        case _Mode.signUp:
          final open = await st.api.signUp(email, pass.text);
          TextInput.finishAutofillContext();
          if (open) {
            await st.updateSettings(country: st.country, language: st.language);
          } else if (mounted) {
            setState(() {
              waitingFor = email;
              mode = _Mode.signIn;
            });
          }
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
      if (!mounted) return;
      if (e.message == Api.notConfirmed) setState(() => waitingFor = email);
      showMsg(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> google() async {
    final st = StateScope.of(context);
    setState(() => busy = true);
    try {
      await st.api.signInWithGoogle(web: kIsWeb);
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
    final st = StateScope.of(context);
    final country = countryByCode(st.country);
    return Scaffold(
      backgroundColor: SaccoLook.of(context).brand,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandHeader(title: st.t('SACCO Ledger'), line: 'Every shilling, on the record'),
                  const SizedBox(height: 24),
                  RiseIn(
                    delay: const Duration(milliseconds: 200),
                    child: SaccoCard(
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (waitingFor != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(Icons.mark_email_unread_outlined, color: cs.onPrimaryContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text('Check your email',
                                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer))),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(
                                    'We sent a link to $waitingFor. Click it to prove the email is yours, then sign in here. '
                                    'No email after a few minutes? Check Spam, or send it again.',
                                    style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                                  ),
                                  Wrap(spacing: 8, children: [
                                    TextButton.icon(onPressed: busy ? null : resend, icon: const Icon(Icons.refresh), label: const Text('Send the link again')),
                                    TextButton(onPressed: () => setState(() => waitingFor = null), child: const Text('Use another email')),
                                  ]),
                                ]),
                              ),
                              gap,
                            ],
                            Text(
                                switch (mode) {
                                  _Mode.signIn => 'Sign in',
                                  _Mode.signUp => 'Create account',
                                  _Mode.reset => 'Forgot password',
                                },
                                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            gap,
                            DropdownButtonFormField<String>(
                              initialValue: st.country,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Country', prefixIcon: Icon(Icons.public)),
                              items: [
                                for (final c in countries) DropdownMenuItem(value: c.code, child: Text('${c.flag}  ${c.name}  (+${c.dial})')),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                st.updateSettings(country: v);
                                if (mode == _Mode.signUp) {
                                  st.updateSettings(language: countryByCode(v).language);
                                }
                              },
                            ),
                            gap,
                            TextField(
                              controller: id,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: mode == _Mode.signUp ? 'Email' : 'Phone or email',
                                helperText: mode == _Mode.signUp
                                    ? 'Your real email. We send a link to prove it is yours.'
                                    : 'Phone like ${country.example} (we add +${country.dial}), or your email',
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                            ),
                            if (mode == _Mode.signUp) ...[
                              gap,
                              Text('Language', style: tt.labelLarge),
                              const SizedBox(height: 6),
                              Wrap(spacing: 8, children: [
                                for (final l in AppLanguage.values)
                                  ChoiceChip(label: Text(l.label), selected: st.language == l, onSelected: (_) => st.updateSettings(language: l)),
                              ]),
                            ],
                            gap,
                            if (mode == _Mode.reset) ...[
                              TextField(
                                controller: code,
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(labelText: 'Code from your group secretary'),
                              ),
                              gap,
                            ],
                            TextField(
                              controller: pass,
                              obscureText: hide,
                              textInputAction: TextInputAction.done,
                              autofillHints: [mode == _Mode.signIn ? AutofillHints.password : AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: mode == _Mode.reset ? 'New password' : 'Password',
                                helperText: mode == _Mode.signIn ? null : 'At least 6 characters',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: hide ? 'Show password' : 'Hide password',
                                  icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => hide = !hide),
                                ),
                              ),
                              onSubmitted: (_) => submit(),
                            ),
                            gap,
                            FilledButton(
                              onPressed: busy ? null : submit,
                              child: busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(switch (mode) {
                                      _Mode.signIn => 'Sign in',
                                      _Mode.signUp => 'Create account',
                                      _Mode.reset => 'Change password',
                                    }),
                            ),
                            if (mode != _Mode.reset) ...[
                              const SizedBox(height: 12),
                              const Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                                  Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: busy ? null : google,
                                icon: Image.asset('assets/brands/google.png', width: 20, height: 20),
                                label: const Text('Continue with Google'),
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (mode != _Mode.signIn) TextButton(onPressed: () => setState(() => mode = _Mode.signIn), child: const Text('Back to sign in')),
                            if (mode == _Mode.signIn) ...[
                              TextButton(onPressed: () => setState(() => mode = _Mode.signUp), child: const Text('New here? Create account')),
                              TextButton(onPressed: () => setState(() => mode = _Mode.reset), child: const Text('Forgot password?')),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We never hold your money. We keep the records.',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(color: SaccoLook.of(context).onBrandMuted),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: SaccoLook.of(context).onBrand),
                    onPressed: () => showPrivacyPolicy(context),
                    child: const Text('Privacy policy'),
                  ),
                  // On the website, members can get the Android app straight from here.
                  if (kIsWeb && !Uri.base.path.contains('SACCO-LEDGER')) // not on the GitHub Pages copy, which has no APK
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.base.resolve('/download/sacco-ledger.apk')),
                      style: TextButton.styleFrom(foregroundColor: cs.onPrimary),
                      icon: const Icon(Icons.android),
                      label: const Text('Get the Android app'),
                    ),
                ],
              ),
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

  /// Joining or starting a group needs the data notice ticked first.
  bool _agreed() {
    if (!agree) showMsg(context, 'Please tick the data notice first.', error: true);
    return agree;
  }

  Future<void> run(Future<String?> Function() fn) async {
    if (!_agreed()) return;
    setState(() => busy = true);
    final st = StateScope.of(context);
    try {
      final select = await fn();
      await st.refresh(select: select);
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
    var country = countryByCode(st.country);
    var currency = country.currency;
    final share = TextEditingController(text: Money.plain(suggestedSharePrice(currency), currency));
    var edition = Edition.vsla;
    var more = false;
    final interest = TextEditingController(text: '10');
    final multiplier = TextEditingController(text: '3');
    final quorum = TextEditingController(text: '67');
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Create your group',
        confirm: 'Create',
        fields: (ctx, set) => [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          TextField(
            controller: me,
            decoration: const InputDecoration(labelText: 'Your full name'),
          ),
          DropdownButtonFormField<String>(
            initialValue: country.code,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Country'),
            items: [for (final c in countries) DropdownMenuItem(value: c.code, child: Text('${c.flag}  ${c.name}'))],
            onChanged: (v) => set(() {
              country = countryByCode(v);
              currency = country.currency;
              share.text = Money.plain(suggestedSharePrice(currency), currency);
            }),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Your phone', helperText: 'Like ${country.example}'),
          ),
          DropdownButtonFormField<Edition>(
            initialValue: edition,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type of group'),
            items: [for (final e in Edition.values) DropdownMenuItem(value: e, child: Text(e.label))],
            onChanged: (v) => set(() => edition = v ?? edition),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(currency),
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Currency', helperText: 'Cannot change after money is recorded'),
            items: [
              for (final c in {for (final k in countries) k.currency}) DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => set(() => currency = v ?? currency),
          ),
          TextField(
            controller: share,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Price of one share ($currency)'),
          ),
          TextButton.icon(
            onPressed: () => set(() => more = !more),
            icon: Icon(more ? Icons.expand_less : Icons.expand_more),
            label: Text(more ? 'Fewer settings' : 'More settings (loans, meetings)'),
          ),
          if (more) ...[
            TextField(
              controller: interest,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Interest rate (% per year)', helperText: 'Most groups use 10'),
            ),
            TextField(
              controller: multiplier,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Biggest loan (times the member\'s savings)', helperText: 'Most groups use 3'),
            ),
            TextField(
              controller: quorum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Members needed for a meeting (%)', helperText: 'Most groups use 67 (two thirds)'),
            ),
          ],
          const EmptyNote('You can change all of these later in Group Settings.'),
        ],
        onConfirm: (ctx) async {
          final nav = Navigator.of(ctx);
          final price = Money.parse(share.text, currency);
          final rate = int.tryParse(interest.text.trim());
          final times = int.tryParse(multiplier.text.trim());
          final q = int.tryParse(quorum.text.trim());
          if (name.text.trim().length < 2 || me.text.trim().length < 2 || price == null) {
            showMsg(ctx, 'Fill in group name, your name and share price.', error: true);
            return;
          }
          if (rate == null || rate < 0 || rate > 100 || times == null || times < 1 || times > 20 || q == null || q < 1 || q > 100) {
            showMsg(ctx, 'Check the extra settings: interest 0-100, loan times 1-20, meeting 1-100%.', error: true);
            return;
          }
          final String id;
          try {
            id = await st.api.createOrganization(
              name: name.text.trim(),
              edition: edition.code,
              currency: currency,
              sharePrice: price,
              multiplier: times,
              interest: rate,
              quorum: q,
              myName: me.text.trim(),
              myPhone: Phones.normalize(phone.text, dial: country.dial) ?? '',
            );
          } on ApiError catch (e) {
            if (ctx.mounted) showMsg(ctx, e.message, error: true);
            return;
          }
          // The group now exists, so the dialog closes whatever happens next: pressing Create again would make a second group.
          // The database's create_organization takes neither the country nor the new loan rules yet.
          String? err;
          try {
            await st.api.setOrgCountry(id, country.code);
            await st.api.setLoanRules(id, {'interest_mode': 'yearly', 'interest_rate': rate});
          } on ApiError catch (e) {
            err = e.message;
          }
          await st.refresh(select: id);
          nav.pop();
          if (err != null && mounted) showMsg(context, 'Group made, but its country or interest was not saved: $err Set them in Group Settings.', error: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: SaccoLook.of(context).brand,
        foregroundColor: Colors.white,
        title: const Text('Welcome'),
        actions: [
          IconButton(icon: const Icon(Icons.account_circle), tooltip: 'My Account', onPressed: () => openAccount(context)),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: st.signOut),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Join my group', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Text('Your secretary gives you an 8-letter code.'),
                      gap,
                      TextField(
                        controller: code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Invite code'),
                      ),
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SaccoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Start a new group', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      gap,
                      FilledButton.tonal(
                        onPressed: busy
                            ? null
                            : () {
                                if (_agreed()) createGroup();
                              },
                        child: const Text('Create group'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                          onPressed: busy ? null : () => run(() => st.api.seedDemo('Me (demo admin)')), child: const Text('Look around the shared demo')),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

/// Common slips in email addresses ("gmial.com"). Returns the fixed address, or null if it looks fine.
String? emailTypo(String email) {
  final at = email.lastIndexOf('@');
  if (at < 1) return null;
  final domain = email.substring(at + 1);
  const fixes = {
    'gmial.com': 'gmail.com',
    'gmai.com': 'gmail.com',
    'gmal.com': 'gmail.com',
    'gamil.com': 'gmail.com',
    'gnail.com': 'gmail.com',
    'gmail.co': 'gmail.com',
    'gmail.con': 'gmail.com',
    'gmail.cm': 'gmail.com',
    'gmail.om': 'gmail.com',
    'gmaill.com': 'gmail.com',
    'gmail': 'gmail.com',
    'yahoo.co': 'yahoo.com',
    'yaho.com': 'yahoo.com',
    'yahooo.com': 'yahoo.com',
    'yahoo.con': 'yahoo.com',
    'hotmal.com': 'hotmail.com',
    'hotmai.com': 'hotmail.com',
    'hotmail.co': 'hotmail.com',
    'hotmail.con': 'hotmail.com',
    'outlok.com': 'outlook.com',
    'outlook.co': 'outlook.com',
    'outlook.con': 'outlook.com',
    'iclod.com': 'icloud.com',
    'icloud.co': 'icloud.com',
  };
  final f = fixes[domain];
  return f == null ? null : '${email.substring(0, at)}@$f';
}
