import 'package:flutter/material.dart';

import '../../core/countries.dart';
import '../../core/config.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../widgets.dart';
import 'circles_screen.dart';
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
    share.text = Money.plain(o.i('share_price'), o.s('currency_code'));
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
    final edit = st.role.isOrgAdmin;
    return AppPageView(
      children: [
        const SectionTitle('Group Settings'),
        if (!edit) const LookOnlyNote(what: 'the settings'),
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
              : (v) {
                  if (v != null) runAndTell(context, () => st.api.setOrgCountry(st.orgId, v), done: 'Country saved.');
                },
        ),
        TextField(
          controller: share,
          enabled: edit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Share price (${st.currency})'),
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
                    await runAndTell(
                        context,
                        () => st.api.updateOrganization(st.orgId, {
                              'name': name.text,
                              'share_price': Money.parse(share.text, st.currency),
                              'max_loan_multiplier': int.tryParse(mult.text.trim()),
                              'meeting_quorum_pct': int.tryParse(quorum.text.trim()),
                              'mtn_merchant_code': mtn.text.trim(),
                              'airtel_merchant_code': airtel.text.trim(),
                            }),
                        done: 'Saved.');
                    if (mounted) setState(() => busy = false);
                  },
            child: const Text('Save'),
          ),
        const LoanRulesCard(),
        if (AppConfig.onlinePayments && st.role.handlesMoney) const GatewaySetupCard(),
        const Divider(),
        OutlinedButton.icon(onPressed: st.signOut, icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ],
    );
  }
}
