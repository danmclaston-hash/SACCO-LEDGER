import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/licences.dart';
import '../../core/money.dart';
import '../theme.dart';
import '../widgets.dart';

class LicencesScreen extends StatelessWidget {
  const LicencesScreen({super.key});

  void _edit(BuildContext context) {
    final st = StateScope.of(context);
    final o = st.org!;
    final type = TextEditingController(text: o.s('licence_type'));
    final number = TextEditingController(text: o.s('licence_number'));
    final expiry = TextEditingController(text: o.s('licence_expiry'));
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Our Group Licence',
        confirm: 'Save',
        fields: (ctx, set) => [
          TextField(
            controller: type,
            decoration: const InputDecoration(labelText: 'Type (e.g. UMRA SACCO licence)'),
          ),
          TextField(
            controller: number,
            decoration: const InputDecoration(labelText: 'Licence number from the certificate'),
          ),
          TextField(
            controller: expiry,
            decoration: const InputDecoration(labelText: 'Expiry date (YYYY-MM-DD)'),
          ),
        ],
        onConfirm: (ctx) async {
          if (expiry.text.trim().isNotEmpty && DateTime.tryParse(expiry.text.trim()) == null) {
            showMsg(ctx, 'Write the date like 2026-12-31.', error: true);
            return;
          }
          await runAndClose(
              ctx, () => st.api.updateOrganization(st.orgId, {'licence_type': type.text, 'licence_number': number.text, 'licence_expiry': expiry.text.trim()}),
              done: 'Saved.');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final o = st.org!;
    final expiry = DateTime.tryParse(o.s('licence_expiry'));
    final days = expiry?.difference(DateTime.now()).inDays;
    return AppPageView(
      children: [
        SaccoCard(
          color: cs.secondaryContainer,
          child: Text(licenceDisclaimer, style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer)),
        ),
        SaccoCard(
          elevation: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Our Group Licence', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  if (days != null)
                    Pill(
                      text: days < 0 ? 'EXPIRED' : (days <= 90 ? 'RENEW NOW: $days days' : 'VALID'),
                      color: days < 0 ? cs.error : (days <= 90 ? warnOrange : okGreen),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (o.n('licence_number') == null) const EmptyNote('No licence recorded for this group yet.'),
              if (o.n('licence_number') != null) ...[
                KeyValue('Type', o.s('licence_type')),
                KeyValue('Number', o.s('licence_number')),
                KeyValue('Expires', Dates.day(o['licence_expiry'])),
              ],
              if (st.role.isOrgAdmin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => _edit(context), child: const Text('Update')),
                ),
            ],
          ),
        ),
        const SectionTitle('For each group or SACCO'),
        for (final l in groupLicences) _LicenceCard(l),
        const SectionTitle('For the company running this app'),
        for (final l in platformLicences) _LicenceCard(l),
        const SectionTitle('Only if you later move money'),
        for (final l in futureLicences) _LicenceCard(l),
      ],
    );
  }
}

class _LicenceCard extends StatelessWidget {
  final LicenceItem l;
  const _LicenceCard(this.l);
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SaccoCard(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.name, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text('${l.regulator} • ${l.law}', style: tt.labelSmall?.copyWith(color: cs.primary)),
          const SizedBox(height: 4),
          Text(l.why, style: tt.bodySmall),
        ],
      ),
    );
  }
}
