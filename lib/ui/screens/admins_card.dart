import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../widgets.dart';

/// Who may open the admin website as a platform administrator.
/// Everyone here can see the list. Only the owner can add or remove people.
/// People always choose their own password: you add an email, never a password.
class AdminsCard extends StatefulWidget {
  const AdminsCard({super.key});
  @override
  State<AdminsCard> createState() => _AdminsCardState();
}

class _AdminsCardState extends State<AdminsCard> {
  int reload = 0;
  bool busy = false;
  final email = TextEditingController();
  final search = TextEditingController();
  List<Json> found = const [];

  @override
  void dispose() {
    email.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() fn) async {
    setState(() => busy = true);
    try {
      final msg = await fn();
      if (mounted) showMsg(context, msg);
      reload++;
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _add(String e) => _run(() async {
        final r = await StateScope.of(context).api.addPlatformAdmin(e);
        email.clear();
        found = const [];
        return r.s('status') == 'added'
            ? '${r.s('email')} is now an administrator.'
            : '${r.s('email')} has not signed up yet. They become administrator when they sign up with this email.';
      });

  Future<void> _search() async {
    final q = search.text.trim();
    if (q.length < 2) return showMsg(context, 'Type at least 2 letters.', error: true);
    try {
      final r = await StateScope.of(context).api.searchUsers(q);
      setState(() => found = r);
      if (r.isEmpty && mounted) showMsg(context, 'Nobody found. Add them by email instead.');
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Json>(
      key: ValueKey(reload),
      future: st.api.platformAdmins(),
      builder: (context, snap) {
        if (snap.hasError) return SaccoCard(child: Text(snap.error.toString()));
        if (!snap.hasData) return const SizedBox.shrink();
        final d = snap.data!;
        final owner = d.b('me_owner');
        return SaccoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Administrators (${d.l('admins').length})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                owner ? 'You are the owner. Only you can add or remove administrators.' : 'Only the owner can add or remove administrators.',
                style: tt.bodySmall,
              ),
              for (final a in d.l('admins'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.s('role') == 'owner' ? Icons.workspace_premium : Icons.admin_panel_settings, color: cs.primary),
                  title: Text('${a.n('name') ?? a.s('email')}${a.b('is_me') ? ' (you)' : ''}'),
                  subtitle: Text('${a.s('email')} • ${a.s('role') == 'owner' ? 'Owner' : 'Admin'} since ${Dates.day(a['added_at'])}'
                      '${a.n('added_by') != null ? ' • added by ${a.s('added_by')}' : ''}'),
                  trailing: owner && a.s('role') != 'owner'
                      ? TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Remove administrator?'),
                                      content: Text('${a.s('email')} will lose admin access at once. Their account stays.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  await _run(() async {
                                    await st.api.removePlatformAdmin(a.s('user_id'));
                                    return '${a.s('email')} is no longer an administrator.';
                                  });
                                },
                          child: const Text('Remove'),
                        )
                      : null,
                ),
              for (final i in d.l('invites'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(i.s('email')),
                  subtitle: Text('Waiting for sign-up • invited ${Dates.day(i['invited_at'])}'),
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
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Their email'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: busy ? null : () => _add(email.text), child: const Text('Add')),
                ]),
                gap,
                Text('Or find someone who already signed up', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      decoration: const InputDecoration(labelText: 'Name or email'),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(onPressed: _search, child: const Text('Search')),
                ]),
                for (final u in found)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(u.n('name') ?? u.s('email')),
                    subtitle: Text(u.s('email')),
                    trailing:
                        u.b('is_admin') ? const Text('Admin') : TextButton(onPressed: busy ? null : () => _add(u.s('email')), child: const Text('Make admin')),
                  ),
              ],
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
