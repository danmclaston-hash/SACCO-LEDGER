import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../widgets.dart';

/// For you, the platform owner: every group, its size, and licence expiry.
class PlatformScreen extends StatelessWidget {
  const PlatformScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Json>>(
      future: st.api.platformOverview(),
      builder: (context, snap) {
        if (snap.hasError) return AppPageView(children: [Text(snap.error.toString())]);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return AppPageView(children: [
          SectionTitle('All Groups (${snap.data!.length})'),
          for (final o in snap.data!)
            SaccoCard(
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.s('name'), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${editionNames[o.s('edition')]} • ${o.s('currency_code')} • Cycle ${o.i('cycle_number')}',
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    Text('${o.i('members')} members • ${o.i('journals')} journals • ${o.i('pending')} pending',
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    Text(
                        o.n('licence_number') == null
                            ? 'No licence recorded'
                            : '${o.s('licence_type')} ${o.s('licence_number')}, expires ${Dates.day(o['licence_expiry'])}',
                        style: tt.labelSmall),
                  ]),
                ),
                TextButton(
                  onPressed: () {
                    final match = st.orgs.where((x) => x.s('id') == o.s('id'));
                    if (match.isNotEmpty) st.selectOrg(match.first);
                  },
                  child: const Text('Open'),
                ),
              ]),
            ),
        ]);
      },
    );
  }
}
