import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Pay online": the group's OWN Flutterwave or Pesapal account takes the money.
/// Nobody types a transaction ID. The gateway reports it, our server checks it again, then it posts.
class OnlinePayCard extends StatefulWidget {
  const OnlinePayCard({super.key});
  @override
  State<OnlinePayCard> createState() => _OnlinePayCardState();
}

class _OnlinePayCardState extends State<OnlinePayCard> with WidgetsBindingObserver {
  int reload = 0;
  String? _justStarted; // checked automatically when the person comes back from the payment page
  final Set<String> _checking = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _justStarted != null) _check(_justStarted!, quiet: true);
  }

  Future<void> _check(String id, {bool quiet = false}) async {
    if (_checking.contains(id)) return;
    setState(() => _checking.add(id));
    final st = StateScope.of(context);
    String msg;
    var bad = false;
    try {
      final r = await st.api.checkOnlinePayment(id);
      msg = switch (r.s('status')) {
        'paid' => 'Paid and recorded. The gateway confirmed it.',
        'failed' => 'Not paid. ${r.s('verify_note')}',
        'needs_review' => 'Money arrived, but an officer must check it: ${r.s('verify_note')}',
        _ => 'Not paid yet. Finish on the payment page, then tap Check again.',
      };
      if (r.s('status') != 'waiting') _justStarted = null;
      bad = r.s('status') == 'failed';
      await st.refresh();
    } catch (e) {
      msg = e.toString();
      bad = true;
    }
    if (!mounted) return;
    setState(() {
      _checking.remove(id);
      reload++;
    });
    if (!quiet || msg.startsWith('Paid')) showMsg(context, msg, error: bad);
  }

  Future<void> _open(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) showMsg(context, 'Could not open the payment page. Link copied: paste it in your browser.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return FutureBuilder<List<dynamic>>(
      key: ValueKey('${st.orgId}-$reload'),
      future: Future.wait([st.api.gatewayStatus(st.orgId), st.api.onlinePayments(st.orgId)]),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final status = snap.data![0] as Json;
        final list = snap.data![1] as List<Json>;
        if (!status.b('enabled') && list.isEmpty) return const SizedBox.shrink();
        return SaccoCard(
          elevation: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.verified_user, color: cs.primary),
                const SizedBox(width: 8),
                Flexible(child: Text('Pay online (checked automatically)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                const InfoTip('verified_payment'),
                const Spacer(),
                if (status.n('mode') == 'test') const Pill(text: 'TEST MONEY', color: warnOrange),
              ]),
              const SizedBox(height: 6),
              Text(
                status.b('enabled')
                    ? 'Pay with ${gatewayNames[status.s('gateway')]} into your group\'s own account. '
                        'No transaction ID to type: the gateway confirms it and it joins the ledger by itself.'
                    : 'Online payment is switched off for this group.',
                style: tt.bodySmall,
              ),
              if (status.b('enabled')) ...[
                gap,
                FilledButton.icon(
                  onPressed: st.myMemberId == null
                      ? null
                      : () async {
                          final r = await showDialog<Json>(context: context, builder: (_) => const _PayOnlineDialog());
                          if (r == null) return;
                          _justStarted = r.s('id');
                          setState(() => reload++);
                          await _open(r.s('checkout_url'));
                        },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Pay online'),
                ),
              ],
              if (list.isNotEmpty) ...[
                gap,
                Text('Online payments', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                for (final p in list.take(10))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('${purposeNames[p.s('purpose')]} • ${money(context, p.i('amount'))} • ${p.s('member_name')}',
                                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          StatusPill(p.s('status')),
                        ]),
                        Text(
                          '${Dates.dayTime(p['created_at'])} • Ref ${p.s('tx_ref')}'
                          '${p.n('gateway_tx_id') != null ? ' • ${gatewayNames[p.s('gateway')]} ID ${p.s('gateway_tx_id')}' : ''}'
                          '${p.n('gateway_ref') != null ? ' • Receipt ${p.s('gateway_ref')}' : ''}',
                          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (p.n('verify_note') != null) Text(p.s('verify_note'), style: tt.labelSmall),
                        if (p.s('status') == 'waiting' || p.s('status') == 'failed')
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if (p.n('checkout_url') != null) TextButton(onPressed: () => _open(p.s('checkout_url')), child: const Text('Open page')),
                            TextButton(
                              onPressed: _checking.contains(p.s('id')) ? null : () => _check(p.s('id')),
                              child: Text(_checking.contains(p.s('id')) ? 'Checking...' : 'Check'),
                            ),
                          ]),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PayOnlineDialog extends StatefulWidget {
  const _PayOnlineDialog();
  @override
  State<_PayOnlineDialog> createState() => _PayOnlineDialogState();
}

class _PayOnlineDialogState extends State<_PayOnlineDialog> {
  String purpose = 'savings';
  String? memberId;
  String? loanId;
  String? goalId;
  final amount = TextEditingController();
  final shares = TextEditingController(text: '1');

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    memberId ??= st.myMemberId;
    final price = st.org!.i('share_price');
    final count = int.tryParse(shares.text.trim()) ?? 0;
    final memberLoans = st.loans.where((l) => l.s('member_id') == memberId && l.s('status') == 'active').toList();
    if (!memberLoans.any((l) => l.s('id') == loanId)) loanId = memberLoans.isEmpty ? null : memberLoans.first.s('id');
    return FormDialog(
      title: 'Pay online',
      confirm: 'Go to payment',
      fields: (ctx, _) => [
        DropdownButtonFormField<String>(
          initialValue: purpose,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'What is it for?'),
          items: [
            for (final p in ['shares', 'savings', 'fine', 'loan_repayment', 'emergency_contribution'])
              DropdownMenuItem(value: p, child: Text(purposeNames[p]!)),
          ],
          onChanged: (v) => setState(() => purpose = v ?? purpose),
        ),
        if (st.canRecordForOthers) MemberPicker(label: 'Member', value: memberId, members: st.activeMembers, onChanged: (v) => setState(() => memberId = v)),
        if (purpose == 'loan_repayment')
          memberLoans.isEmpty
              ? const EmptyNote('This member has no active loan.')
              : DropdownButtonFormField<String>(
                  key: ValueKey(memberId),
                  initialValue: loanId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Loan'),
                  items: [
                    for (final l in memberLoans)
                      DropdownMenuItem(value: l.s('id'), child: Text('${l.s('loan_number')} • left ${money(context, l.i('remaining'))}')),
                  ],
                  onChanged: (v) => setState(() => loanId = v),
                ),
        if (purpose == 'shares') ...[
          TextField(
            controller: shares,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Number of shares (${money(context, price)} each)'),
            onChanged: (_) => setState(() {}),
          ),
          Text('Total: ${money(context, count * price)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ] else
          MoneyField(controller: amount, label: 'Amount', currency: st.currency),
        if ((purpose == 'shares' || purpose == 'savings') && st.activeGoals.isNotEmpty)
          DropdownButtonFormField<String?>(
            initialValue: st.activeGoals.any((g) => g.s('id') == goalId) ? goalId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Is this for a goal?'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Not for any goal')),
              for (final g in st.activeGoals) DropdownMenuItem<String?>(value: g.s('id'), child: Text(g.s('name'), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => goalId = v),
          ),
        const EmptyNote('Next: a secure payment page opens. Pay there with mobile money or card. Then come back here.'),
      ],
      onConfirm: (ctx) async {
        final nav = Navigator.of(ctx);
        final value = purpose == 'shares' ? count * price : Money.parse(amount.text, st.currency);
        if (value == null || value <= 0) {
          showMsg(ctx, 'Enter a valid amount.', error: true);
          return;
        }
        if (purpose == 'loan_repayment' && loanId == null) {
          showMsg(ctx, 'Choose a loan.', error: true);
          return;
        }
        try {
          final r = await st.api.startOnlinePayment(
            st.orgId,
            memberId: memberId!,
            purpose: purpose,
            amount: value,
            loanId: purpose == 'loan_repayment' ? loanId : null,
            goalId: purpose == 'shares' || purpose == 'savings' ? goalId : null,
          );
          nav.pop(r);
        } catch (e) {
          if (ctx.mounted) showMsg(ctx, e.toString(), error: true);
        }
      },
    );
  }
}

/// Group Settings: connect the group's OWN gateway account. Admin or treasurer only.
/// Keys go to our server, which tests them with the gateway and locks them. Nobody can read them back.
class GatewaySetupCard extends StatefulWidget {
  const GatewaySetupCard({super.key});
  @override
  State<GatewaySetupCard> createState() => _GatewaySetupCardState();
}

class _GatewaySetupCardState extends State<GatewaySetupCard> {
  int reload = 0;
  bool editing = false;
  bool busy = false;
  String gateway = 'flutterwave';
  String mode = 'live';
  String? webhookUrl;
  final k1 = TextEditingController();
  final k2 = TextEditingController();

  @override
  void dispose() {
    k1.dispose();
    k2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final st = StateScope.of(context);
    setState(() => busy = true);
    try {
      final keys = gateway == 'flutterwave'
          ? {'secret_key': k1.text.trim(), 'webhook_hash': k2.text.trim()}
          : {'consumer_key': k1.text.trim(), 'consumer_secret': k2.text.trim()};
      final r = await st.api.saveGatewayKeys(st.orgId, gateway: gateway, mode: mode, keys: keys);
      k1.clear();
      k2.clear();
      webhookUrl = r.n('webhook_url');
      editing = false;
      reload++;
      if (mounted) showMsg(context, 'Connected. The keys worked and are now locked on the server.');
    } catch (e) {
      if (mounted) showMsg(context, e.toString(), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final isDemo = st.org!.b('is_demo');
    if (!isDemo && mode == 'test') mode = 'live';
    return FutureBuilder<Json>(
      key: ValueKey('${st.orgId}-$reload'),
      future: st.api.gatewayStatus(st.orgId),
      builder: (context, snap) {
        final s = snap.data ?? const <String, dynamic>{};
        return SaccoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Online payments', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Connect your group\'s OWN Flutterwave or Pesapal account. Money goes straight to the group. '
                'Each payment is confirmed by the gateway and checked again by our server, so nobody types a transaction ID.',
                style: tt.bodySmall,
              ),
              gap,
              if (snap.hasError) Text(snap.error.toString()),
              if (s.b('enabled'))
                Text(
                  'Connected: ${gatewayNames[s.s('gateway')]} • ${s.s('mode') == 'test' ? 'TEST money' : 'LIVE'} • key ending ${s.s('key_hint')}\n'
                  'By ${s.s('updated_by')} on ${Dates.dayTime(s['updated_at'])}',
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                )
              else if (snap.hasData)
                const Text('Not connected.'),
              if (webhookUrl != null) ...[
                gap,
                SelectableText(
                  gateway == 'flutterwave'
                      ? 'Last step: in Flutterwave go to Settings → Webhooks. Paste this URL, and type the same secret hash you entered here:\n$webhookUrl'
                      : 'Pesapal notifications are set up already. Nothing else to do.',
                  style: tt.bodySmall,
                ),
              ],
              if (!editing) ...[
                gap,
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonal(
                    onPressed: () => setState(() => editing = true),
                    child: Text(s.b('enabled') ? 'Change keys' : 'Connect a gateway'),
                  ),
                  if (s.b('enabled'))
                    OutlinedButton(
                      onPressed: () async {
                        final err = await st.act(() => st.api.disableGateway(st.orgId));
                        if (context.mounted) showMsg(context, err ?? 'Online payments switched off.', error: err != null);
                        setState(() => reload++);
                      },
                      child: const Text('Switch off'),
                    ),
                ]),
              ] else ...[
                gap,
                DropdownButtonFormField<String>(
                  initialValue: gateway,
                  decoration: const InputDecoration(labelText: 'Gateway'),
                  items: const [
                    DropdownMenuItem(value: 'flutterwave', child: Text('Flutterwave (30+ African countries)')),
                    DropdownMenuItem(value: 'pesapal', child: Text('Pesapal (East and Southern Africa)')),
                  ],
                  onChanged: (v) => setState(() {
                    gateway = v ?? gateway;
                    k1.clear();
                    k2.clear();
                  }),
                ),
                gap,
                DropdownButtonFormField<String>(
                  key: ValueKey(isDemo),
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Money'),
                  items: [
                    const DropdownMenuItem(value: 'live', child: Text('Live: real money')),
                    if (isDemo) const DropdownMenuItem(value: 'test', child: Text('Test: pretend money (demo group only)')),
                  ],
                  onChanged: (v) => setState(() => mode = v ?? mode),
                ),
                gap,
                TextField(
                  controller: k1,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: gateway == 'flutterwave' ? 'Secret key (starts FLWSECK)' : 'Consumer key'),
                ),
                gap,
                TextField(
                  controller: k2,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: gateway == 'flutterwave' ? 'Webhook secret hash (make up a long password)' : 'Consumer secret',
                  ),
                ),
                gap,
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: busy ? null : () => setState(() => editing = false), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : _save,
                    child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test and save'),
                  ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}
