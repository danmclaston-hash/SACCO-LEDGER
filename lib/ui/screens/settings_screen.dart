import 'package:flutter/material.dart';

import '../../core/countries.dart';
import '../../core/json.dart';
import '../widgets.dart';
import 'loan_calculator.dart';
import 'online_pay.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final name = TextEditingController();
  final share = TextEditingController();
  final mult = TextEditingController();
  final quorum = TextEditingController();
  final mtn = TextEditingController();
  final airtel = TextEditingController();
  String? _loadedFor;
  bool busy = false;

  void _load(Json o) {
    if (_loadedFor == o.s('id')) return;
    _loadedFor = o.s('id');
    name.text = o.s('name');
    share.text = o.s('share_price');
    mult.text = o.s('max_loan_multiplier');
    quorum.text = o.s('meeting_quorum_pct');
    mtn.text = o.s('mtn_merchant_code');
    airtel.text = o.s('airtel_merchant_code');
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final o = st.org!;
    _load(o);
    final edit = st.isOrgAdmin;
    return AppPageView(
      children: [
        const SectionTitle('Group Settings'),
        TextField(
          controller: name,
          enabled: edit,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(o.s('country_code')),
          initialValue: countryByCode(o.n('country_code')).code,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Country', helperText: 'Sets the phone code. Money stays in ${st.currency}.'),
          items: [for (final c in countries) DropdownMenuItem(value: c.code, child: Text('${c.flag}  ${c.name}  (+${c.dial})'))],
          onChanged: !edit
              ? null
              : (v) async {
                  if (v == null) return;
                  final err = await st.act(() async {
                    await st.api.setOrgCountry(st.orgId, v);
                    await st.loadOrgs(select: st.orgId); // the group's details come with the group list
                  });
                  if (context.mounted) showMsg(context, err ?? 'Country saved.', error: err != null);
                },
        ),
        TextField(
          controller: share,
          enabled: edit,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Share price (${st.currency}, smallest unit)'),
        ),
        TextField(
          controller: mult,
          enabled: edit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Loan limit (times savings)'),
        ),
        TextField(
          controller: quorum,
          enabled: edit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Meeting quorum (%)'),
        ),
        const SectionTitle('Group Payment Accounts', info: 'merchant_code'),
        const EmptyNote('Your group\'s OWN merchant codes or numbers. Members pay here directly. The app never receives this money.'),
        TextField(
          controller: mtn,
          enabled: edit,
          decoration: const InputDecoration(
            labelText: 'MTN MoMo merchant code or number',
            prefixIcon: Padding(padding: EdgeInsets.all(12), child: BrandMark('mtn_momo')),
          ),
        ),
        TextField(
          controller: airtel,
          enabled: edit,
          decoration: const InputDecoration(
            labelText: 'Airtel Money merchant code or number',
            prefixIcon: Padding(padding: EdgeInsets.all(12), child: BrandMark('airtel_money')),
          ),
        ),
        if (edit)
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    final err = await st.act(() async {
                      await st.api.updateOrganization(st.orgId, {
                        'name': name.text,
                        'share_price': int.tryParse(share.text.trim()),
                        'max_loan_multiplier': int.tryParse(mult.text.trim()),
                        'meeting_quorum_pct': int.tryParse(quorum.text.trim()),
                        'mtn_merchant_code': mtn.text.trim(),
                        'airtel_merchant_code': airtel.text.trim(),
                      });
                      await st.loadOrgs(select: st.orgId);
                    });
                    if (mounted) setState(() => busy = false);
                    if (context.mounted) showMsg(context, err ?? 'Saved.', error: err != null);
                  },
            child: const Text('Save'),
          ),
        const LoanRulesCard(),
        if (st.canReview) const GatewaySetupCard(),
        const Divider(),
        OutlinedButton.icon(onPressed: st.signOut, icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ],
    );
  }
}
