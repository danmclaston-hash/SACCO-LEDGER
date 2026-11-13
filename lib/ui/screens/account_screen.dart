import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../../core/app_lock.dart';
import '../../core/i18n.dart';
import '../../core/names.dart';
import '../../core/pages.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../tour.dart';
import '../widgets.dart';
import 'two_step.dart';

/// Opens My Account on top of whatever screen is showing (used where there is no side menu).
void openAccount(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('My Account'), backgroundColor: SaccoLook.of(context).brand, foregroundColor: Colors.white),
        body: const AccountScreen(),
      ),
    ),
  );
}

/// The person's own space: who they are, how they sign in, how the app looks, and their data.
/// Nothing here changes group money records.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final a = st.account;
    if (a.isEmpty) {
      return AppPageView(
        children: [
          const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
          ),
          Center(
            child: TextButton(onPressed: st.loadAccount, child: const Text('Reload')),
          ),
        ],
      );
    }
    return AppPageView(
      children: [
        const _Header(),
        const _ProfileCard(),
        const _SecurityCard(),
        const _LookCard(),
        const _PrivacyCard(),
        OutlinedButton.icon(
          onPressed: () async {
            final nav = Navigator.of(context);
            await st.signOut();
            if (nav.canPop()) nav.popUntil((r) => r.isFirst);
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double size;
  const Avatar({super.key, required this.name, this.photo, this.size = 40});

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (photo != null && photo!.isNotEmpty) {
      try {
        bytes = base64Decode(photo!);
      } catch (_) {}
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: SaccoLook.of(context).accent,
      foregroundImage: bytes == null ? null : MemoryImage(bytes),
      child: Text(
        initials(name),
        style: TextStyle(color: SaccoLook.of(context).onAccent, fontWeight: FontWeight.bold, fontSize: size * 0.38),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final a = st.account;
    final tt = Theme.of(context).textTheme;
    final groups = a.l('memberships').where((m) => m.b('is_active')).toList();
    final look = SaccoLook.of(context);
    return SaccoCard(
      color: look.brand,
      child: Row(
        children: [
          Avatar(name: a.s('full_name'), photo: a.n('avatar'), size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.s('full_name').isEmpty ? 'No name yet' : a.s('full_name'),
                  style: tt.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text('Signs in with ${Phones.signInLabel(a.s('sign_in_id'))}', style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => st.goTo(AppPage.circles),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('In ${groups.length} ${groups.length == 1 ? 'circle' : 'circles'} • See my circles ›',
                            style: tt.bodyMedium?.copyWith(color: look.onBrand, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (st.platform.b('team')) Pill(text: 'Platform team', color: look.accent, foreground: look.onAccent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final List<Widget> children;
  const _Section({required this.icon, required this.title, required this.hint, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SaccoCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: Icon(icon, color: cs.primary)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2, bottom: 4),
            child: Text(hint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.color});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        minTileHeight: 56,
        leading: ExcludeSemantics(child: Icon(icon, color: color)),
        title: Text(title, style: TextStyle(color: color)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final a = st.account;
    return _Section(
      icon: Icons.badge_outlined,
      title: 'Profile',
      hint: 'Your name, phone and photo.',
      children: [
        _Row(
          icon: Icons.edit_outlined,
          title: 'Name and phone',
          subtitle: '${a.s('full_name')} • ${Money.maskPhone(a.n('phone'))}',
          onTap: () => _editProfile(context, st),
        ),
        _Row(
          icon: Icons.photo_camera_outlined,
          title: a.n('avatar') == null ? 'Add photo' : 'Change photo',
          subtitle: 'Shown on your account. Small photos only.',
          onTap: () => _pickPhoto(context, st),
          trailing: a.n('avatar') == null
              ? null
              : TextButton(
                  onPressed: () => runAndTell(context, () => st.api.updateMyProfile({'avatar': ''}), done: 'Photo removed.'),
                  child: const Text('Remove'),
                ),
        ),
        _Row(icon: Icons.password, title: 'Change password', subtitle: 'You need your current password.', onTap: () => _changePassword(context, st)),
      ],
    );
  }

  void _editProfile(BuildContext context, AppState st) {
    final a = st.account;
    final name = TextEditingController(text: a.s('full_name'));
    final phone = TextEditingController(text: a.s('phone'));
    var applyToGroups = true;
    final key = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Name and phone',
        confirm: 'Save',
        fields: (ctx, set) => [
          Form(
            key: key,
            child: Column(
              children: [
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Write at least 2 letters.' : null,
                ),
                gap,
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(labelText: 'Phone', helperText: 'Like 0772 123456'),
                  validator: (v) {
                    final n = Phones.normalize(v, dial: st.dial);
                    return n == null || Phones.isValidNumber(n) ? null : 'Phone looks wrong.';
                  },
                ),
              ],
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: applyToGroups,
            onChanged: (v) => set(() => applyToGroups = v ?? true),
            title: const Text('Also update my card in my groups'),
            subtitle: const Text('Officers see the change in the audit trail.'),
          ),
          const Text('This does not change the phone you sign in with.', style: TextStyle(fontSize: 12)),
        ],
        onConfirm: (ctx) async {
          if (!(key.currentState?.validate() ?? false)) return;
          await runAndClose(
              ctx,
              () => st.api.updateMyProfile(
                  {'full_name': name.text.trim(), 'phone': Phones.normalize(phone.text, dial: st.dial) ?? '', 'apply_to_groups': applyToGroups}),
              done: 'Saved.');
        },
      ),
    );
  }

  Future<void> _pickPhoto(BuildContext context, AppState st) async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final raw = await files.first.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      if (context.mounted) showMsg(context, 'That file is not a photo we can read.', error: true);
      return;
    }
    // Square crop, 256 px, JPEG: about 20 KB. Keeps the database small and cheap.
    final side = decoded.width < decoded.height ? decoded.width : decoded.height;
    final square = img.copyCrop(decoded, x: (decoded.width - side) ~/ 2, y: (decoded.height - side) ~/ 2, width: side, height: side);
    final small = img.copyResize(square, width: 256, height: 256, interpolation: img.Interpolation.average);
    final jpg = img.encodeJpg(small, quality: 80);
    if (context.mounted) await runAndTell(context, () => st.api.updateMyProfile({'avatar': base64Encode(jpg)}), done: 'Photo saved.');
  }

  void _changePassword(BuildContext context, AppState st) {
    final current = TextEditingController();
    final next = TextEditingController();
    final again = TextEditingController();
    final key = GlobalKey<FormState>();
    var hide = true;
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Change password',
        confirm: 'Change',
        fields: (ctx, set) => [
          Form(
            key: key,
            child: AutofillGroup(
              child: Column(
                children: [
                  TextFormField(
                    controller: current,
                    obscureText: hide,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      suffixIcon: IconButton(
                        tooltip: hide ? 'Show passwords' : 'Hide passwords',
                        icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => set(() => hide = !hide),
                      ),
                    ),
                    validator: (v) => (v ?? '').isEmpty ? 'Type your current password.' : null,
                  ),
                  gap,
                  TextFormField(
                    controller: next,
                    obscureText: hide,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters. Longer is safer.'),
                    validator: (v) {
                      if ((v ?? '').length < 8) return 'Use at least 8 characters.';
                      if (v == current.text) return 'Choose a different password.';
                      return null;
                    },
                  ),
                  gap,
                  TextFormField(
                    controller: again,
                    obscureText: hide,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'New password again'),
                    validator: (v) => v != next.text ? 'The two new passwords are different.' : null,
                  ),
                ],
              ),
            ),
          ),
        ],
        onConfirm: (ctx) async {
          if (!(key.currentState?.validate() ?? false)) return;
          await runAndClose(ctx, () => st.api.changePassword(st.account.s('sign_in_id'), current.text, next.text), done: 'Password changed.');
        },
      ),
    );
  }
}

class _SecurityCard extends StatefulWidget {
  const _SecurityCard();
  @override
  State<_SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends State<_SecurityCard> {
  bool? bioAvailable;
  bool showAll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (bioAvailable == null) {
      StateScope.of(context).biometricsAvailable().then((v) {
        if (mounted) setState(() => bioAvailable = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final signIns = st.account.l('sign_ins');
    final shown = showAll ? signIns : signIns.take(3).toList();
    final tt = Theme.of(context).textTheme;
    return _Section(
      icon: Icons.shield_outlined,
      title: 'Security',
      hint: 'Stop others using your account on a shared or lost phone.',
      children: [
        _Row(
          icon: Icons.pin_outlined,
          title: 'App lock PIN',
          subtitle: st.hasPin ? 'On. Asks after 1 minute away. Only on this device.' : 'Off. Ask for a PIN when the app opens.',
          trailing: Switch(
            value: st.hasPin,
            onChanged: (on) async {
              if (on) {
                final pin = await _askNewPin(context);
                if (pin == null) return;
                await st.setPin(pin);
                if (context.mounted) showMsg(context, 'App lock is on.');
              } else {
                await st.removePin();
                if (context.mounted) showMsg(context, 'App lock is off.');
              }
            },
          ),
        ),
        if (st.hasPin && bioAvailable == true)
          _Row(
            icon: Icons.fingerprint,
            title: 'Unlock with fingerprint or face',
            subtitle: 'The PIN still works too.',
            trailing: Switch(value: st.useBiometrics, onChanged: st.setBiometrics),
          ),
        const TwoStepTile(),
        _Row(
          icon: Icons.devices_other,
          title: 'Sign out of all devices',
          subtitle: 'Lost a phone? This ends every session, this one too.',
          onTap: () => _signOutEverywhere(context, st),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Text('Recent sign-ins', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (signIns.isEmpty) const Padding(padding: EdgeInsets.all(4), child: EmptyNote('No sign-ins recorded yet.')),
        for (final s in shown)
          _Row(
            icon: s.s('platform') == 'web' ? Icons.computer : Icons.phone_android,
            title: Dates.dayTime(s['at']),
            subtitle: '${s.s('device')} • ${s.s('platform')}',
          ),
        if (signIns.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => showAll = !showAll), child: Text(showAll ? 'Show fewer' : 'Show all ${signIns.length}')),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Not you? Change your password, then sign out of all devices.',
            style: tt.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Future<String?> _askNewPin(BuildContext context) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? result;
    await showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Choose an app PIN',
        confirm: 'Turn on',
        fields: (ctx, set) => [
          const Text('4 to 6 numbers. Not your MoMo PIN. Forgot it? Sign in again with your password.'),
          TextField(
            controller: first,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'PIN'),
          ),
          TextField(
            controller: second,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'PIN again'),
          ),
        ],
        onConfirm: (ctx) async {
          if (!PinLock.validPin(first.text)) {
            showMsg(ctx, 'Use 4 to 6 numbers.', error: true);
            return;
          }
          if (first.text != second.text) {
            showMsg(ctx, 'The two PINs are different.', error: true);
            return;
          }
          result = first.text;
          Navigator.of(ctx).pop();
        },
      ),
    );
    return result;
  }

  Future<void> _signOutEverywhere(BuildContext context, AppState st) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of all devices?'),
        content: const Text('Every phone and browser using your account will be signed out, this one too. Records you saved are not lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out everywhere')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    await st.signOut(everywhere: true);
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
  }
}

const _textSizes = <(double, String)>[(0.9, 'Small'), (1.0, 'Normal'), (1.15, 'Large'), (1.3, 'Extra large')];

class _LookCard extends StatelessWidget {
  const _LookCard();

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    Future<void> save(Future<String?> f) async {
      final err = await f;
      if (err != null && context.mounted) showMsg(context, err, error: true);
    }

    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(t, style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
        );

    return _Section(
      icon: Icons.palette_outlined,
      title: 'Look and language',
      hint: 'Saved on your account, so it follows you to any phone.',
      children: [
        label('Look'),
        Row(
          children: [
            for (final l in AppLook.values) ...[
              Expanded(child: _LookSwatch(l, selected: st.look == l, onTap: () => save(st.updateSettings(look: l)))),
              if (l != AppLook.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
        label('Light or dark'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {st.themeMode},
            onSelectionChanged: (s) => save(st.updateSettings(theme: s.first)),
          ),
        ),
        label('Text size'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (v, name) in _textSizes)
              ChoiceChip(
                label: Text(name),
                selected: (st.textScale - v).abs() < 0.01,
                onSelected: (_) => save(st.updateSettings(scale: v)),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text('Example: Savings UGX 25,000', style: tt.bodyMedium),
        ),
        label('Language'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in AppLanguage.values)
              ChoiceChip(
                label: Text(l.label),
                selected: st.language == l,
                onSelected: (_) => save(st.updateSettings(language: l)),
              ),
          ],
        ),
        label('Help'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.showTips,
          onChanged: (v) => save(st.updateSettings(showTips: v)),
          title: const Text('Explain words with (i) buttons'),
          subtitle: const Text('Small buttons next to words like share-out and ledger.'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => showTour(context), icon: const Icon(Icons.slideshow), label: const Text('Show the welcome tour again')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Text(
            'Only some words are translated so far. The rest stay in English.',
            style: tt.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// A small picture of a look: its page, its top strip and its main button.
class _LookSwatch extends StatelessWidget {
  final AppLook look;
  final bool selected;
  final VoidCallback onTap;
  const _LookSwatch(this.look, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = themeFor(look, Theme.of(context).brightness);
    final x = t.extension<SaccoLook>()!;
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(x.radius * 0.7), side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2.5 : 1));
    return Semantics(
      button: true,
      selected: selected,
      label: '${look.label}: ${look.hint}',
      excludeSemantics: true,
      child: Material(
        color: t.scaffoldBackgroundColor,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 26, color: x.brand),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(look.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: t.textTheme.bodyMedium?.fontFamily, fontWeight: FontWeight.w700, color: t.colorScheme.onSurface)),
                        ),
                        if (selected) Icon(Icons.check_circle, size: 18, color: t.colorScheme.primary),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                            width: 44,
                            height: 20,
                            decoration:
                                BoxDecoration(color: x.isPassbook ? t.colorScheme.primary : x.accent, borderRadius: BorderRadius.circular(x.radius * 0.3))),
                        const SizedBox(width: 6),
                        Container(
                          width: 44,
                          height: 20,
                          decoration: BoxDecoration(
                              color: t.colorScheme.surface,
                              border: Border.all(color: t.colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(x.radius * 0.3)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final a = st.account;
    final cs = Theme.of(context).colorScheme;
    final req = a.m('deletion_request');
    final pending = req.s('status') == 'pending';
    return _Section(
      icon: Icons.privacy_tip_outlined,
      title: 'Privacy and my data',
      hint: 'What you agreed to, and your copy of your records.',
      children: [
        for (final g in a.l('memberships'))
          _Row(
            icon: Icons.verified_user_outlined,
            title: g.s('org_name'),
            subtitle: g.n('consent_at') == null
                ? 'Added by the group. Member M${g.i('member_no')}${g.b('is_active') ? '' : ' • left'}'
                : 'Agreed to the data notice on ${Dates.day(g['consent_at'])}${g.b('is_active') ? '' : ' • left'}',
          ),
        _Row(
          icon: Icons.policy_outlined,
          title: 'Privacy policy',
          subtitle: 'What we keep, why, and your rights.',
          onTap: () => showPrivacyPolicy(context),
        ),
        _Row(
          icon: Icons.download_outlined,
          title: 'Download my data',
          subtitle: 'One file with your profile, statements, payments and loans.',
          onTap: () => _export(context, st),
        ),
        if (pending)
          _Row(
            icon: Icons.hourglass_top,
            title: 'Account closing requested',
            subtitle: 'Asked on ${Dates.day(req['requested_at'])}. Changed your mind?',
            trailing: TextButton(
              onPressed: () => runAndTell(context, st.api.cancelDeletion, done: 'Request cancelled.'),
              child: const Text('Cancel'),
            ),
          )
        else
          _Row(
            icon: Icons.person_remove_outlined,
            title: 'Close my account',
            subtitle: 'Your money records stay, as groups must keep proof.',
            color: cs.error,
            onTap: () => _close(context, st),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context, AppState st) async {
    try {
      final data = await st.api.exportMyData();
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
      final name = 'my-sacco-ledger-data-${Dates.iso(DateTime.now())}.json';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/json', name: name)],
          fileNameOverrides: [name],
          subject: 'My SACCO Ledger data',
        ),
      );
    } catch (e) {
      if (context.mounted) showMsg(context, e.toString(), error: true);
    }
  }

  void _close(BuildContext context, AppState st) {
    final reason = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Close my account?',
        confirm: 'Send request',
        fields: (ctx, set) => [
          const Text(
            'What happens:\n'
            '• You leave every group and can no longer sign in to them.\n'
            '• Your photo, phone and sign-in history are removed.\n'
            '• Past payments and loans stay, with your name, because groups must keep proof.\n\n'
            'Download your data first if you want a copy.',
          ),
          TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Why? (optional)'),
          ),
        ],
        onConfirm: (ctx) => runAndClose(ctx, () => st.api.requestDeletion(reason.text), done: 'Request sent. You can cancel it until it is done.'),
      ),
    );
  }
}
