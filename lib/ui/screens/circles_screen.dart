import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/catalog.dart';
import '../../core/config.dart';
import '../../core/countries.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/pages.dart';
import '../../data/api.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth_screen.dart';

/// What a role means, in one short line a person can read at a glance.
String roleMeaning(Role r) => switch (r) {
      Role.orgAdmin => 'You run this circle: settings, roles and checks.',
      Role.treasurer => 'You check and confirm the money records.',
      Role.secretary => 'You keep the members list and the meetings.',
      Role.loanOfficer => 'You look at loan requests.',
      Role.auditor => 'You can see everything, to check it. You change nothing.',
      Role.member => 'You save, borrow and see your own records.',
      Role.platformAdmin => 'Platform team: you can look, not change.',
    };

/// "an Admin", "a Treasurer".
String withArticle(Role r) {
  final l = r == Role.orgAdmin ? 'Admin' : r.label;
  return '${'AEIOU'.contains(l[0]) ? 'an' : 'a'} $l';
}

/// The circle's mark: its first letters on the brand colour.
class CircleMark extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final Color? foreground;
  const CircleMark(this.name, {super.key, this.size = 48, this.color, this.foreground});

  @override
  Widget build(BuildContext context) {
    final look = SaccoLook.of(context);
    final cs = Theme.of(context).colorScheme;
    // The brand colour disappears on a dark page, so dark mode uses the lighter tint.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ?? (dark ? cs.primaryContainer : look.brand);
    final fg = foreground ?? (dark ? cs.onPrimaryContainer : look.onBrand);
    final words = name.replaceAll(RegExp(r'\(.*?\)'), '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final letters = words.isEmpty ? '?' : (words.length == 1 ? words.first.substring(0, 1) : '${words[0][0]}${words[1][0]}').toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(look.isPassbook ? 6 : size * 0.3)),
        child: Text(letters, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.36, letterSpacing: 0.5)),
      ),
    );
  }
}

/// The pill that says my role in a circle. Admin wears the accent colour, officers the primary tint, members a quiet grey.
class RoleBadge extends StatelessWidget {
  final Role role;
  const RoleBadge(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final look = SaccoLook.of(context);
    final (Color bg, Color fg, IconData icon) = switch (role) {
      Role.orgAdmin => (look.accent, look.onAccent, Icons.workspace_premium_rounded),
      Role.member => (cs.surfaceContainerHighest, cs.onSurface, Icons.person_rounded),
      Role.platformAdmin => (cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.visibility_rounded),
      _ => (cs.primaryContainer, cs.onPrimaryContainer, Icons.badge_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(look.isPassbook ? 4 : 20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 4),
        Text(role == Role.orgAdmin ? 'Admin' : role.short, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Every circle I am in, grouped by what I do there, my invitations, and the doors to start or join another.
class CirclesScreen extends StatelessWidget {
  const CirclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final mine = st.myCircles;
    final lead = mine.where((o) => o.s('my_role') == Role.orgAdmin.code).toList();
    final help = mine.where((o) => Role.parse(o.s('my_role')).isOfficer && o.s('my_role') != Role.orgAdmin.code).toList();
    final member = mine.where((o) => o.s('my_role') == Role.member.code).toList();
    final canInvite = st.canSeeAllGroups || mine.any((o) => Role.parse(o.s('my_role')).canManageMembers && !o.b('is_demo'));
    final lookOnly = st.lookOnlyCircles;

    return AppPageView(
      children: [
        RiseIn(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(st.t('My circles'), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              mine.isEmpty ? 'You are not in a circle yet.' : 'You are in ${mine.length} ${mine.length == 1 ? 'circle' : 'circles'}. Tap one to open it.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        if (st.invites.isNotEmpty) const InvitesPanel(),
        if (lead.isNotEmpty) _Section(title: 'I lead', icon: Icons.workspace_premium_rounded, circles: lead),
        if (help.isNotEmpty) _Section(title: 'I help run', icon: Icons.badge_rounded, circles: help),
        if (member.isNotEmpty) _Section(title: 'I am a member', icon: Icons.person_rounded, circles: member),
        RiseIn(
          delay: const Duration(milliseconds: 120),
          child: SaccoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Another circle?', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Your circles stay separate. Money and members never mix between them.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              gap,
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => showCreateCircle(context, askConsent: true),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Start a new circle'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showJoinWithCode(context),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('Join with a code'),
                ),
                if (canInvite)
                  OutlinedButton.icon(
                    onPressed: () => showInviteDialog(context),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Invite someone'),
                  ),
              ]),
            ]),
          ),
        ),
        if (lookOnly.isNotEmpty)
          SaccoCard(
            color: cs.surfaceContainerHighest,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.visibility_rounded, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${lookOnly.length} other ${lookOnly.length == 1 ? 'circle' : 'circles'} on the platform',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 6),
              const Text('As the platform team you can look at these, but not change them. '
                  'To run one, invite yourself as its admin (the circle sees this in its audit trail), or ask its admin to invite you.'),
              if (st.canSee(AppPage.platform)) ...[
                gap,
                OutlinedButton(onPressed: () => st.goTo(AppPage.platform), child: const Text('See all groups')),
              ],
            ]),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Json> circles;
  const _Section({required this.title, required this.icon, required this.circles});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RiseIn(
      delay: const Duration(milliseconds: 60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text('$title (${circles.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
          ]),
        ),
        for (final o in circles) Padding(padding: const EdgeInsets.only(bottom: 10), child: CircleTile(o)),
      ]),
    );
  }
}

/// One circle I am in: its mark, size, money, my role and what that role means.
class CircleTile extends StatelessWidget {
  final Json circle;
  const CircleTile(this.circle, {super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final role = Role.parse(circle.s('my_role'));
    final here = circle.s('id') == st.orgId;
    final people = circle.i('people');
    return Semantics(
      button: true,
      label: '${circle.s('name')}. You are ${withArticle(role)}.${here ? ' Open now.' : ''}',
      excludeSemantics: true,
      child: Material(
        color: here ? cs.primaryContainer.withValues(alpha: 0.45) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(look.radius),
          side: BorderSide(color: here ? cs.primary : cs.outlineVariant, width: here ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: here ? () => st.goTo(AppPage.overview) : () => st.selectOrg(circle),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleMark(circle.s('name')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(circle.s('name'), maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '$people ${people == 1 ? 'person' : 'people'} • ${circle.s('currency_code')} • ${Edition.parse(circle.s('edition')).title}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    RoleBadge(role),
                    if (here) Pill(text: 'OPEN NOW', color: cs.primary, foreground: cs.onPrimary),
                    if (circle.b('is_demo')) Pill(text: 'DEMO', color: look.warn),
                  ]),
                  const SizedBox(height: 6),
                  Text(roleMeaning(role), style: tt.bodySmall),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Circles that invited me. Shows on My circles, the welcome screen and the home page.
class InvitesPanel extends StatelessWidget {
  const InvitesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, inv) in st.invites.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RiseIn(delay: Duration(milliseconds: 60 * i), child: InviteCard(inv)),
          ),
      ],
    );
  }
}

/// A warm, clear invitation: which circle, who asked, as what, and one big button.
class InviteCard extends StatelessWidget {
  final Json invite;
  const InviteCard(this.invite, {super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final role = Role.parse(invite.s('role'));
    final people = invite.i('people');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: look.brand, borderRadius: BorderRadius.circular(look.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mark_email_unread_rounded, color: look.accent, size: 20),
          const SizedBox(width: 6),
          Text('YOU ARE INVITED', style: tt.labelMedium?.copyWith(color: look.accent, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          CircleMark(invite.s('org_name'), size: 52, color: look.accent, foreground: look.onAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(invite.s('org_name'), style: tt.titleLarge?.copyWith(color: look.onBrand, fontWeight: FontWeight.w800)),
              Text('$people ${people == 1 ? 'person' : 'people'} • ${invite.s('currency_code')}', style: tt.bodySmall?.copyWith(color: look.onBrandMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text('${invite.s('invited_by')} would like you to join as ${withArticle(role)}.', style: tt.bodyLarge?.copyWith(color: look.onBrand)),
        if (invite.n('message') != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: look.onBrand.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(look.radius * 0.6)),
            child: Text('"${invite.s('message')}"', style: tt.bodyMedium?.copyWith(color: look.onBrand, fontStyle: FontStyle.italic)),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: look.accent, foregroundColor: look.onAccent, minimumSize: const Size(0, 48)),
            onPressed: () => showJoinSheet(context, invite),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('See and join'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: look.onBrand, minimumSize: const Size(0, 48)),
            onPressed: () => _decline(context, invite),
            child: const Text('No, thanks'),
          ),
        ]),
      ]),
    );
  }
}

Future<void> _decline(BuildContext context, Json invite) async {
  final st = StateScope.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Say no to ${invite.s('org_name')}?'),
      content: const Text('The invitation goes away. If you change your mind, ask them for a new one.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Say no')),
      ],
    ),
  );
  if (sure != true || !context.mounted) return;
  if (await runAndTell(context, () => st.api.declineInvite(invite.s('code')), done: 'Done. You said no to ${invite.s('org_name')}.')) {
    if (st.pendingJoin == invite.s('code')) await st.clearPendingJoin();
  }
}

/// The full invitation: what the circle is, what joining means, and the person's own details, filled from their profile.
Future<void> showJoinSheet(BuildContext context, Json invite) {
  final st = StateScope.of(context);
  final role = Role.parse(invite.s('role'));
  final country = countryByCode(invite.n('country_code'));
  final name = TextEditingController(text: st.account.s('full_name'));
  final phone = TextEditingController(text: Phones.local(st.account.s('phone'), dial: country.dial));
  var agreed = false;
  var busy = false;
  String? error;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final tt = Theme.of(ctx).textTheme;
      final cs = Theme.of(ctx).colorScheme;
      final look = SaccoLook.of(ctx);

      Future<void> join() async {
        if (!agreed) {
          set(() => error = 'Please tick the data notice first.');
          return;
        }
        if (name.text.trim().length < 2) {
          set(() => error = 'Write your name.');
          return;
        }
        final p = phone.text.trim();
        final normal = p.isEmpty ? null : Phones.normalize(p, dial: country.dial);
        if (p.isNotEmpty && !Phones.isValidNumber(normal)) {
          set(() => error = 'That phone looks wrong. Write it like ${country.example}, or leave it empty.');
          return;
        }
        set(() {
          busy = true;
          error = null;
        });
        final nav = Navigator.of(ctx);
        try {
          final org = await st.api.acceptInvite(invite.s('code'), name: name.text.trim(), phone: normal);
          await st.clearPendingJoin();
          await st.refresh(select: org);
          nav.pop();
          if (context.mounted) showMsg(context, 'Welcome to ${invite.s('org_name')}! You are now ${withArticle(role)}.');
        } on ApiError catch (e) {
          set(() {
            busy = false;
            error = e.message;
          });
        }
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RiseIn(
                  child: Column(children: [
                    CircleMark(invite.s('org_name'), size: 72),
                    const SizedBox(height: 12),
                    Text('You are invited to join', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    Text(invite.s('org_name'), textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('${invite.s('invited_by')} invited you as ${withArticle(role)}.', textAlign: TextAlign.center, style: tt.bodyMedium),
                  ]),
                ),
                const SizedBox(height: 16),
                SaccoCard(
                  color: cs.secondaryContainer,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.diversity_3_rounded, color: cs.onSecondaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is another circle inside SACCO Ledger. Joining adds it next to your other circles. '
                        'Nothing in them changes, and their money never mixes. Switch between circles any time from the top bar or My circles.',
                        style: tt.bodyMedium?.copyWith(color: cs.onSecondaryContainer),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('About this circle', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (invite.n('admin_name') != null) KeyValue('Run by', invite.s('admin_name')),
                KeyValue('People', '${invite.i('people')}'),
                KeyValue('Money', invite.s('currency_code')),
                KeyValue('Type', Edition.parse(invite.s('edition')).title),
                KeyValue('Your role', '${role == Role.orgAdmin ? 'Admin' : role.label}: ${roleMeaning(role)}'),
                KeyValue('Invitation ends', Dates.day(invite['expires_at'])),
                if (invite.n('message') != null) ...[
                  const SizedBox(height: 8),
                  Text('"${invite.s('message')}"', style: tt.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 16),
                Text('Your details for this circle', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('Filled from your profile. Fix them if needed. This circle\'s officers will see them.', style: tt.bodySmall),
                gap,
                TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your full name')),
                gap,
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: 'Your phone (optional)', helperText: 'Like ${country.example}'),
                ),
                gap,
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: agreed,
                  onChanged: (v) => set(() => agreed = v ?? false),
                  title: const Text('Data notice', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(dataNotice),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: look.accent, foregroundColor: look.onAccent, minimumSize: const Size.fromHeight(52)),
                  onPressed: busy ? null : join,
                  child: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Join ${invite.s('org_name')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          st.clearPendingJoin();
                          Navigator.of(ctx).pop();
                        },
                  child: const Text('Not now'),
                ),
              ]),
            ),
          ),
        ),
      );
    }),
  );
}

/// Opens an invitation from its code. Returns false when the code is not an invitation (it may be an ordinary join code).
Future<bool> openInviteCode(BuildContext context, String code) async {
  final st = StateScope.of(context);
  try {
    final inv = await st.api.inviteDetails(code);
    if (inv == null) return false;
    if (!context.mounted) return true;
    if (inv.b('already_member')) {
      await st.clearPendingJoin();
      final o = st.orgs.where((x) => x.s('id') == inv.s('org_id')).firstOrNull;
      if (o != null) await st.selectOrg(o);
      if (context.mounted) showMsg(context, 'You are already in ${inv.s('org_name')}.');
      return true;
    }
    await showJoinSheet(context, inv);
    // Shown once from the link. It stays in My circles until they answer.
    await st.clearPendingJoin();
  } on ApiError catch (e) {
    await st.clearPendingJoin();
    if (context.mounted) showMsg(context, e.message, error: true);
  }
  return true;
}

/// One box for every kind of code: an invitation code opens the invitation, an old member code links the person.
Future<void> showJoinWithCode(BuildContext context) {
  final st = StateScope.of(context);
  final code = TextEditingController();
  var agreed = false;
  return showDialog(
    context: context,
    builder: (_) => FormDialog(
      title: 'Join with a code',
      confirm: 'Next',
      fields: (ctx, set) => [
        const Text('Type the 8-letter code from your invitation or from the circle\'s secretary.'),
        TextField(
          controller: code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(8)],
          decoration: const InputDecoration(labelText: 'Code'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: agreed,
          onChanged: (v) => set(() => agreed = v ?? false),
          title: const Text('Data notice', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text(dataNotice),
        ),
      ],
      onConfirm: (ctx) async {
        final c = code.text.trim().toUpperCase();
        if (c.length != 8) {
          showMsg(ctx, 'The code has 8 letters and numbers.', error: true);
          return;
        }
        final nav = Navigator.of(ctx);
        try {
          final inv = await st.api.inviteDetails(c);
          if (inv != null) {
            nav.pop();
            if (context.mounted) await openInviteCode(context, c);
            return;
          }
        } on ApiError catch (e) {
          if (ctx.mounted) showMsg(ctx, e.message, error: true);
          return;
        }
        if (!agreed) {
          if (ctx.mounted) showMsg(ctx, 'Please tick the data notice first.', error: true);
          return;
        }
        if (!ctx.mounted) return;
        await runAndClose(ctx, () => st.api.claimInvite(c), done: 'You are in. Find the circle in My circles.');
      },
    ),
  );
}

/// The link a person taps to open their invitation.
String inviteLink(String code) => '${AppConfig.siteUrl}/?join=$code';

/// Invite a person by email. Circle admins and secretaries invite to their own circle; the platform team to any circle.
/// The platform team can also search people who already have an account.
Future<void> showInviteDialog(BuildContext context, {String? orgId}) async {
  final st = StateScope.of(context);
  List<Json> circles;
  try {
    circles = st.canSeeAllGroups ? await st.api.platformOverview() : st.myCircles.where((o) => Role.parse(o.s('my_role')).canManageMembers).toList();
  } on ApiError catch (e) {
    if (context.mounted) showMsg(context, e.message, error: true);
    return;
  }
  circles = circles.where((o) => !o.b('is_demo')).toList();
  if (orgId != null && circles.every((o) => o.s('id') != orgId)) circles = [...circles, ...st.orgs.where((o) => o.s('id') == orgId)];
  if (circles.isEmpty) {
    if (context.mounted) showMsg(context, 'You can invite people only to a circle you run.', error: true);
    return;
  }
  if (!context.mounted) return;

  var org = orgId ?? (circles.any((o) => o.s('id') == st.orgId) ? st.orgId : circles.first.s('id'));
  var role = Role.member;
  final email = TextEditingController();
  final message = TextEditingController();
  var found = <Json>[];
  Json? picked;
  Timer? wait;

  bool fullPower(String id) => st.canSeeAllGroups || st.orgs.any((o) => o.s('id') == id && o.s('my_role') == Role.orgAdmin.code);

  await showDialog(
    context: context,
    builder: (_) => FormDialog(
      title: 'Invite someone',
      confirm: 'Make invitation',
      fields: (ctx, set) {
        final roles = fullPower(org) ? Role.assignable : const [Role.member];
        if (!roles.contains(role)) role = Role.member;
        return [
          const Text('They get a link and a code. Nobody joins without saying yes.'),
          if (orgId == null || circles.length > 1)
            DropdownButtonFormField<String>(
              initialValue: org,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Circle'),
              items: [for (final o in circles) DropdownMenuItem(value: o.s('id'), child: Text(o.s('name'), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => set(() => org = v ?? org),
            ),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Their email',
              helperText: st.canSeeAllGroups ? 'Type part of an email or name to find people who already have an account.' : null,
              helperMaxLines: 3,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
            ),
            onChanged: (v) {
              picked = null;
              if (!st.canSeeAllGroups) return;
              wait?.cancel();
              final q = v.trim();
              if (q.length < 3) {
                set(() => found = []);
                return;
              }
              wait = Timer(const Duration(milliseconds: 350), () async {
                try {
                  final r = await st.api.searchUsers(q);
                  if (ctx.mounted) set(() => found = r.take(5).toList());
                } on ApiError {
                  // Search is a help only; typing the full email still works.
                }
              });
            },
          ),
          if (picked != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_rounded, color: SaccoLook.of(ctx).ok),
              title: Text(picked!.s('name').isEmpty ? picked!.s('email') : picked!.s('name')),
              subtitle: const Text('Has an account. They will see the invitation in the app too.'),
            )
          else
            for (final u in found)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.person_search_rounded),
                title: Text(u.s('name').isEmpty ? u.s('email') : u.s('name')),
                subtitle: Text(u.s('email')),
                onTap: () => set(() {
                  picked = u;
                  email.text = u.s('email');
                  found = [];
                }),
              ),
          DropdownButtonFormField<Role>(
            key: ValueKey('role-$org'),
            initialValue: role,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Their role', helperText: roleMeaning(role), helperMaxLines: 3),
            items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r == Role.orgAdmin ? 'Admin' : r.label))],
            onChanged: (v) => set(() => role = v ?? role),
          ),
          TextField(
            controller: message,
            maxLength: 280,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'A short welcome (optional)', hintText: 'We meet on Saturdays at 10.'),
          ),
        ];
      },
      onConfirm: (ctx) async {
        final nav = Navigator.of(ctx);
        try {
          final r = await st.api.inviteToCircle(org, email: email.text.trim(), role: role.code, message: message.text.trim());
          wait?.cancel();
          nav.pop();
          if (context.mounted) await showInviteReady(context, r);
        } on ApiError catch (e) {
          if (ctx.mounted) showMsg(ctx, e.message, error: true);
        }
      },
    ),
  );
  wait?.cancel();
}

/// The made invitation: a link to send by WhatsApp or SMS, and the code for typing.
Future<void> showInviteReady(BuildContext context, Json r) {
  final link = inviteLink(r.s('code'));
  final role = Role.parse(r.s('role'));
  final text = 'You are invited to join ${r.s('org_name')} on SACCO Ledger as ${withArticle(role)}. '
      'Tap to see it and join: $link  (or open the app, tap My circles, Join with a code: ${r.s('code')})';
  return showDialog(
    context: context,
    builder: (ctx) {
      final tt = Theme.of(ctx).textTheme;
      final look = SaccoLook.of(ctx);
      return AlertDialog(
        icon: Icon(Icons.mark_email_read_rounded, color: look.ok, size: 40),
        title: const Text('Invitation ready'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Send this to ${r.s('email')}. It works for 14 days, only for that email.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: look.brand, borderRadius: BorderRadius.circular(look.radius * 0.6)),
              child: SelectableText(r.s('code'),
                  textAlign: TextAlign.center,
                  style: look.numbers(tt.headlineMedium).copyWith(color: look.onBrand, fontWeight: FontWeight.w800, letterSpacing: 4)),
            ),
            const SizedBox(height: 10),
            SelectableText(link, textAlign: TextAlign.center, style: tt.bodySmall),
            const SizedBox(height: 12),
            Text(
              r.b('has_account')
                  ? 'They already have an account, so the invitation also waits in their app under My circles.'
                  : 'They have no account yet. When they sign up with this email, the invitation will be waiting.',
              textAlign: TextAlign.center,
              style: tt.bodySmall,
            ),
          ]),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) showMsg(ctx, 'Link copied.');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy link'),
          ),
          TextButton.icon(
            onPressed: () async {
              try {
                await SharePlus.instance.share(ShareParams(text: text, subject: 'Join ${r.s('org_name')}'));
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: text));
                if (ctx.mounted) showMsg(ctx, 'Message copied. Paste it in WhatsApp or SMS.');
              }
            },
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      );
    },
  );
}

/// Officers' list of this circle's invitations, with a cancel button on the open ones.
class CircleInvitesCard extends StatelessWidget {
  const CircleInvitesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Loaded<List<Json>>(
      load: () => st.api.circleInvites(st.orgId),
      waiting: const SizedBox.shrink(),
      error: (_) => const SizedBox.shrink(),
      builder: (context, list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final open = list.where((x) => x.s('status') == 'pending').toList();
        final done = list.where((x) => x.s('status') != 'pending').take(5).toList();
        return SaccoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Invitations (${open.length} open)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            for (final x in [...open, ...done])
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  switch (x.s('status')) {
                    'accepted' => Icons.check_circle_rounded,
                    'pending' => Icons.schedule_rounded,
                    _ => Icons.cancel_outlined,
                  },
                  color: x.s('status') == 'accepted' ? SaccoLook.of(context).ok : cs.onSurfaceVariant,
                ),
                title: Text(x.s('email')),
                subtitle: Text('${Role.labelOf(x.s('role'))} • ${_statusWord(x.s('status'))}'
                    '${x.s('via') == 'platform' ? ' • by the platform team' : ' • by ${x.s('invited_by')}'}'),
                trailing: x.s('status') == 'pending'
                    ? Wrap(spacing: 4, children: [
                        IconButton(
                          tooltip: 'Copy link',
                          icon: const Icon(Icons.link_rounded),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: inviteLink(x.s('code'))));
                            if (context.mounted) showMsg(context, 'Link copied.');
                          },
                        ),
                        IconButton(
                          tooltip: 'Cancel invitation',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => runAndTell(context, () => st.api.cancelInvite(x.s('id')), done: 'Invitation cancelled. The link no longer works.'),
                        ),
                      ])
                    : null,
              ),
          ]),
        );
      },
    );
  }
}

String _statusWord(String s) => switch (s) {
      'pending' => 'waiting',
      'accepted' => 'joined',
      'declined' => 'said no',
      'cancelled' => 'cancelled',
      'expired' => 'expired',
      _ => s,
    };

/// Opens the invitation from a link (?join=CODE) once the person is signed in and unlocked.
class JoinLinkGate extends StatefulWidget {
  final Widget child;
  const JoinLinkGate({super.key, required this.child});
  @override
  State<JoinLinkGate> createState() => _JoinLinkGateState();
}

class _JoinLinkGateState extends State<JoinLinkGate> {
  String? _opening;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final code = st.pendingJoin;
    if (code != null && code != _opening && st.signedIn && !st.locked && !st.booting && !st.loading) {
      _opening = code;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final isInvite = await openInviteCode(this.context, code);
        if (!isInvite && mounted) {
          // Not an invitation: an ordinary member code from an old link.
          await st.clearPendingJoin();
          if (mounted) showMsg(this.context, 'Open My circles and tap "Join with a code" to use $code.');
        }
      });
    }
    return widget.child;
  }
}

/// Small notes at the top of the home page: invitations waiting, and "look only" when the platform team opens a circle.
class CircleNotices extends StatelessWidget {
  const CircleNotices({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final look = SaccoLook.of(context);
    final n = st.invites.length;
    final lookOnly = st.role == Role.platformAdmin;
    if (n == 0 && !lookOnly) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (n > 0)
        RiseIn(
          child: Material(
            color: look.accent,
            borderRadius: BorderRadius.circular(look.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(look.radius),
              onTap: () => st.goTo(AppPage.circles),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.mark_email_unread_rounded, color: look.onAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      n == 1 ? '${st.invites.first.s('org_name')} invited you to join. Tap to see.' : '$n circles invited you to join. Tap to see.',
                      style: TextStyle(color: look.onAccent, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: look.onAccent),
                ]),
              ),
            ),
          ),
        ),
      if (n > 0 && lookOnly) const SizedBox(height: 10),
      if (lookOnly) const LookOnlyNote(),
    ]);
  }
}

/// Says plainly why boxes are grey: the person can look but their role cannot change this.
class LookOnlyNote extends StatelessWidget {
  final String? what;
  const LookOnlyNote({super.key, this.what});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final platform = st.role == Role.platformAdmin;
    final demo = st.org?.b('is_demo') ?? false;
    final text = platform
        ? 'You are looking at this circle as the platform team. You can see it, but only its own admin can change it. '
            'To run it yourself, invite yourself as its admin from My circles (the circle sees this in its audit trail).'
        : demo
            ? 'This is the shared demo. Everyone can look around, nobody can change it. Start your own circle in My circles to try changes.'
            : 'Only this circle\'s admin can change ${what ?? 'these'}. You are ${withArticle(st.role)}, so you can look.';
    return SaccoCard(
      color: cs.surfaceContainerHighest,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Look only', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(text, style: tt.bodyMedium),
            if (platform || demo) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => st.goTo(AppPage.circles), child: const Text('Go to My circles')),
            ],
          ]),
        ),
      ]),
    );
  }
}
