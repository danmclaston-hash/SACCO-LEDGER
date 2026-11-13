import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../widgets.dart';
import 'admins_card.dart';
import 'circles_screen.dart';

/// For you, the platform owner: every group, its size, and licence expiry.
class PlatformScreen extends StatelessWidget {
  const PlatformScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Loaded<List<Json>>(
      load: st.api.platformOverview,
      builder: (context, groups) {
        return AppPageView(
          children: [
            SaccoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Invite someone to a circle', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Find a person by email, pick the circle and their role. They get a link and decide themselves. '
                    'You can invite yourself too, to run a circle you are not in.'),
                gap,
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                      onPressed: () => showInviteDialog(context), icon: const Icon(Icons.mail_outline_rounded), label: const Text('Invite someone')),
                ),
              ]),
            ),
            const AdminsCard(),
            const _DeletionRequests(),
            SectionTitle('All Groups (${groups.length})'),
            Text('You see totals only. To look inside a circle, its admin must open a 24-hour window. Every look is written in that circle\'s record.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            for (final o in groups)
              SaccoCard(
                radius: 12,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.s('name'), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Text(
                            '${Edition.parse(o.s('edition')).label} • ${o.s('currency_code')} • Cycle ${o.i('cycle_number')}',
                            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            '${o.i('members')} members • ${o.i('journals')} records • ${o.i('pending')} waiting',
                            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            o.n('support_until') == null ? 'Locked: totals only' : 'Open for you until ${Dates.dayTime(o['support_until'])}',
                            style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: o.n('support_until') == null ? cs.onSurfaceVariant : cs.primary),
                          ),
                          Text(
                            o.n('licence_number') == null
                                ? 'No licence recorded'
                                : '${o.s('licence_type')} ${o.s('licence_number')}, expires ${Dates.day(o['licence_expiry'])}',
                            style: tt.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (o.n('support_until') != null)
                        TextButton(
                          onPressed: () {
                            final match = st.orgs.where((x) => x.s('id') == o.s('id'));
                            if (match.isNotEmpty) st.selectOrg(match.first);
                          },
                          child: const Text('Look'),
                        ),
                      if (!o.b('is_demo')) TextButton(onPressed: () => showInviteDialog(context, orgId: o.s('id')), child: const Text('Invite')),
                    ]),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// People who asked to close their account. Closing keeps money records but removes personal extras.
class _DeletionRequests extends StatelessWidget {
  const _DeletionRequests();

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Loaded<List<Json>>(
      load: st.api.deletionRequests,
      builder: (context, list) {
        final pending = list.where((d) => d.s('status') == 'pending').toList();
        return SaccoCard(
          color: pending.isEmpty ? null : cs.errorContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account closing requests (${pending.length})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (pending.isEmpty) const Text('None waiting. Data law: answer requests without delay.'),
              for (final d in pending)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${d.s('name')} • ${d.s('sign_in_id')}'),
                  subtitle: Text('Asked ${Dates.day(d['requested_at'])} • ${d.i('groups')} group(s)${d.n('reason') != null ? '\n"${d.s('reason')}"' : ''}'),
                  trailing: FilledButton(
                    onPressed: () async {
                      final note = await askText(context, title: 'Close this account?', label: 'Note for the record', confirm: 'Close account');
                      if (note == null || !context.mounted) return;
                      await runAndTell(context, () => st.api.completeDeletion(d.s('id'), note), done: 'Account closed. Money records kept.');
                    },
                    child: const Text('Close'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
