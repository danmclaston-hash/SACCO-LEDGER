import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../widgets.dart';
import 'admins_card.dart';

/// For you, the platform owner: every group, its size, and licence expiry.
class PlatformScreen extends StatefulWidget {
  const PlatformScreen({super.key});
  @override
  State<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends State<PlatformScreen> {
  int reload = 0;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Json>>(
      key: ValueKey(reload),
      future: st.api.platformOverview(),
      builder: (context, snap) {
        if (snap.hasError) return AppPageView(children: [Text(snap.error.toString())]);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return AppPageView(
          children: [
            const AdminsCard(),
            _DeletionRequests(onChanged: () => setState(() => reload++)),
            SectionTitle('All Groups (${snap.data!.length})'),
            for (final o in snap.data!)
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
                            '${editionNames[o.s('edition')]} • ${o.s('currency_code')} • Cycle ${o.i('cycle_number')}',
                            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            '${o.i('members')} members • ${o.i('journals')} journals • ${o.i('pending')} pending',
                            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
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
                    TextButton(
                      onPressed: () {
                        final match = st.orgs.where((x) => x.s('id') == o.s('id'));
                        if (match.isNotEmpty) st.selectOrg(match.first);
                      },
                      child: const Text('Open'),
                    ),
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
  final VoidCallback onChanged;
  const _DeletionRequests({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Json>>(
      future: st.api.deletionRequests(),
      builder: (context, snap) {
        final list = snap.data ?? const <Json>[];
        final pending = list.where((d) => d.s('status') == 'pending').toList();
        return SaccoCard(
          color: pending.isEmpty ? null : cs.errorContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account closing requests (${pending.length})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (snap.hasError) Text(snap.error.toString()),
              if (snap.hasData && pending.isEmpty) const Text('None waiting. Data law: answer requests without delay.'),
              for (final d in pending)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${d.s('name')} • ${d.s('sign_in_id')}'),
                  subtitle: Text('Asked ${Dates.day(d['requested_at'])} • ${d.i('groups')} group(s)${d.n('reason') != null ? '\n"${d.s('reason')}"' : ''}'),
                  trailing: FilledButton(
                    onPressed: () async {
                      final note = await askText(context, title: 'Close this account?', label: 'Note for the record', confirm: 'Close account');
                      if (note == null) return;
                      final err = await st.act(() => st.api.completeDeletion(d.s('id'), note));
                      if (context.mounted) showMsg(context, err ?? 'Account closed. Money records kept.', error: err != null);
                      onChanged();
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
