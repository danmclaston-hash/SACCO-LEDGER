import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/json.dart';
import '../../core/money.dart';
import '../widgets.dart';
import '../text.dart';

/// The platform team: owners and admins, plus everyone who has signed up.
/// Admins can open every group (read only). Owners can also add, promote and remove team members.
/// The founder can never be removed or demoted. People always choose their own password.
class AdminsCard extends StatefulWidget {
  const AdminsCard({super.key});
  @override
  State<AdminsCard> createState() => _AdminsCardState();
}

class _AdminsCardState extends State<AdminsCard> {
  bool busy = false;
  bool showAll = false;
  String newRole = 'admin';
  String filter = '';
  final email = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() fn) async {
    setState(() => busy = true);
    var msg = '';
    await runAndTell(context, () async => msg = await fn());
    if (!mounted) return;
    if (msg.isNotEmpty) showMsg(context, msg);
    setState(() => busy = false);
  }

  static String _roleName(String r) => r == 'owner' ? 'owner' : 'admin';

  Future<void> _add(String e, String role) => _run(() async {
        final r = await StateScope.of(context).api.addPlatformAdmin(e, role: role);
        email.clear();
        return r.s('status') == 'added'
            ? '${r.s('email')} is now ${role == 'owner' ? 'an owner' : 'an admin'}.'
            : '${r.s('email')} has not signed up yet. They become ${_roleName(role)} the moment they sign up with this email.';
      });

  Future<bool> _confirm(String title, String body, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
          ],
        ),
      ) ==
      true;

  Future<void> _teamAction(Json a, String action) async {
    final api = StateScope.of(context).api;
    final who = a.s('email');
    switch (action) {
      case 'owner':
        if (!await _confirm('Make $who an owner?', 'Owners can add, promote and remove everyone on the team (except the founder).', 'Make owner')) return;
        await _run(() async {
          await api.setPlatformRole(a.s('user_id'), 'owner');
          return '$who is now an owner.';
        });
      case 'admin':
        await _run(() async {
          await api.setPlatformRole(a.s('user_id'), 'admin');
          return '$who is now an admin (no longer an owner).';
        });
      case 'remove':
        if (!await _confirm('Remove $who from the team?', 'They lose platform access at once. Their own account and groups stay.', 'Remove')) return;
        await _run(() async {
          await api.removePlatformAdmin(a.s('user_id'));
          return '$who is no longer on the team.';
        });
    }
  }

  Future<void> _personAction(Json u, String action) async {
    final api = StateScope.of(context).api;
    final who = Phones.signInLabel(u.s('email'));
    switch (action) {
      case 'owner':
        if (!await _confirm('Make $who an owner?', 'Owners can change the whole team (except the founder).', 'Make owner')) return;
        await _add(u.s('email'), 'owner');
      case 'admin':
        await _add(u.s('email'), 'admin');
      case 'block':
        if (!await _confirm('Block $who?',
            'They are signed out everywhere and cannot sign in again. Nothing is deleted: group records stay whole. You can unblock later.', 'Block')) {
          return;
        }
        await _run(() async {
          await api.setAccountBlocked(u.s('user_id'), true);
          return '$who is blocked.';
        });
      case 'unblock':
        await _run(() async {
          await api.setAccountBlocked(u.s('user_id'), false);
          return '$who can sign in again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Loaded<Json>(
      load: st.api.platformAdmins,
      waiting: const SizedBox.shrink(),
      builder: (context, d) {
        final owner = d.b('me_owner');
        final q = filter.trim().toLowerCase();
        final people =
            d.l('people').where((u) => q.isEmpty || u.s('email').toLowerCase().contains(q) || (u.n('name') ?? '').toLowerCase().contains(q)).toList();
        final shown = showAll || q.isNotEmpty ? people : people.take(10).toList();
        final unproved = d.l('people').where((u) => !u.b('checked') && !u.b('blocked')).length;
        Widget roleChip(String r) => Pill(text: r == 'owner' ? 'OWNER' : 'ADMIN', color: r == 'owner' ? cs.primary : cs.secondary);

        return SaccoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('Platform team (${d.l('admins').length})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
              ]),
              Text(
                owner ? 'You are an owner: you can add people, make them owner or admin, and remove them.' : 'Only owners can change the team.',
                style: tt.bodySmall,
              ),
              const SizedBox(height: 4),
              Text('Admin: can open every group to look and help. Owner: an admin who can also change the team.', style: tt.labelSmall),
              for (final a in d.l('admins'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.s('role') == 'owner' ? Icons.workspace_premium : Icons.admin_panel_settings, color: cs.primary),
                  title: Text('${a.n('name') ?? a.s('email')}${a.b('is_me') ? ' (you)' : ''}${a.b('is_founder') ? ' • founder' : ''}'),
                  subtitle: Text('${a.s('email')} • since ${Dates.day(a['added_at'])}${a.n('added_by') != null ? ' • added by ${a.s('added_by')}' : ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    roleChip(a.s('role')),
                    if (owner && !a.b('is_founder') && !a.b('is_me'))
                      PopupMenuButton<String>(
                        enabled: !busy,
                        tooltip: tr('Change'),
                        onSelected: (v) => _teamAction(a, v),
                        itemBuilder: (_) => [
                          if (a.s('role') != 'owner') const PopupMenuItem(value: 'owner', child: Text('Make owner')),
                          if (a.s('role') == 'owner') const PopupMenuItem(value: 'admin', child: Text('Make admin only')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
                        ],
                      ),
                  ]),
                ),
              for (final i in d.l('invites'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(i.s('email')),
                  subtitle: Text('Becomes ${_roleName(i.s('role'))} when they sign up • invited ${Dates.day(i['invited_at'])}'),
                  trailing: owner
                      ? TextButton(
                          onPressed: busy
                              ? null
                              : () => _run(() async {
                                    await st.api.cancelAdminInvite(i.s('email'));
                                    return 'Invite cancelled.';
                                  }),
                          child: const Text('Cancel'),
                        )
                      : null,
                ),
              if (owner) ...[
                const Divider(),
                Text('Add by email', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text('Works even before they sign up. They choose their own password.', style: tt.labelSmall),
                const SizedBox(height: 6),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: 'Their email'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'admin', label: Text('Admin')),
                        ButtonSegment(value: 'owner', label: Text('Owner')),
                      ],
                      selected: {newRole},
                      onSelectionChanged: (v) => setState(() => newRole = v.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: busy ? null : () => _add(email.text, newRole), child: const Text('Add')),
                ]),
              ],
              const Divider(),
              Text('People who signed up (${d.l('people').length})', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                  'Newest first. ✓ = email proved (Google, or clicked our link). '
                  '? = not proved yet${unproved > 0 ? ' ($unproved)' : ''}. Owners can block a fake account; nothing is deleted.',
                  style: tt.labelSmall),
              const SizedBox(height: 6),
              TextField(
                decoration: InputDecoration(labelText: 'Find by name or email', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => filter = v),
              ),
              for (final u in shown)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Tooltip(
                    message: u.b('blocked')
                        ? 'Blocked: cannot sign in'
                        : u.b('checked')
                            ? 'Email proved (${u.s('via') == 'google' ? 'Google' : 'clicked our link'})'
                            : 'Not proved: ${u.s('via') == 'phone' ? 'phone number with no code check' : 'never clicked an email link'}',
                    child: Icon(
                      u.b('blocked') ? Icons.block : (u.b('checked') ? Icons.verified : Icons.help_outline),
                      color: u.b('blocked') ? cs.error : (u.b('checked') ? cs.primary : cs.tertiary),
                    ),
                  ),
                  title: Text(u.n('name') ?? Phones.signInLabel(u.s('email')), overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${u.n('name') != null ? '${Phones.signInLabel(u.s('email'))}\n' : ''}'
                    '${u.b('blocked') ? 'BLOCKED • ' : (u.b('checked') ? '' : 'Not proved • ')}'
                    'Joined ${Dates.day(u['joined_at'])} • '
                    '${u.i('groups')} ${u.i('groups') == 1 ? 'group' : 'groups'}'
                    '${u.n('last_sign_in') != null ? ' • last in ${Dates.day(u['last_sign_in'])}' : ''}',
                  ),
                  isThreeLine: u.n('name') != null,
                  trailing: u.n('role') != null
                      ? roleChip(u.s('role'))
                      : owner
                          ? PopupMenuButton<String>(
                              enabled: !busy,
                              tooltip: tr('Team or block'),
                              icon: const Icon(Icons.more_vert),
                              onSelected: (r) => _personAction(u, r),
                              itemBuilder: (_) => [
                                if (!u.b('blocked')) ...const [
                                  PopupMenuItem(value: 'admin', child: Text('Make admin')),
                                  PopupMenuItem(value: 'owner', child: Text('Make owner')),
                                  PopupMenuItem(value: 'block', child: Text('Block (fake account)')),
                                ],
                                if (u.b('blocked')) const PopupMenuItem(value: 'unblock', child: Text('Unblock')),
                              ],
                            )
                          : null,
                ),
              if (!showAll && q.isEmpty && people.length > shown.length)
                TextButton(onPressed: () => setState(() => showAll = true), child: Text('Show all ${people.length}')),
              if (d.l('history').isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('History (cannot be edited)', style: tt.labelLarge),
                  children: [
                    for (final h in d.l('history'))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${h.s('action').replaceAll('_', ' ').toLowerCase()}: ${h.s('details')}'),
                        subtitle: Text('${h.s('who')} • ${Dates.dayTime(h['at'])}'),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
