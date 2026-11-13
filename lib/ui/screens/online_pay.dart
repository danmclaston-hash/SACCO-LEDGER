import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels_screen.dart';
import '../text.dart';

/// "Pay online": the group's OWN Flutterwave or Pesapal account takes the money.
/// Nobody types a transaction ID. The gateway reports it, our server checks it again, then it posts.
class OnlinePayCard extends StatefulWidget {
  const OnlinePayCard({super.key});
  @override
  State<OnlinePayCard> createState() => _OnlinePayCardState();
}

class _OnlinePayCardState extends State<OnlinePayCard> with WidgetsBindingObserver {
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
    var paid = false;
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
      paid = r.s('status') == 'paid';
      await st.refresh();
    } catch (e) {
      msg = e.toString();
      bad = true;
    }
    if (!mounted) return;
    setState(() => _checking.remove(id));
    if (!quiet || paid) showMsg(context, msg, error: bad);
  }

  Future<void> _open(String url) =>
      openOrCopy(context, Uri.parse(url), copy: url, external: true, failMessage: 'Could not open the payment page. Link copied: paste it in your browser.');

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Groups whose database has no online payments yet see nothing here, not an error.
    return Loaded<List<dynamic>>(
      load: () => Future.wait([st.api.gatewayStatus(st.orgId), st.api.onlinePayments(st.orgId)]),
      waiting: const SizedBox.shrink(),
      error: (_) => const SizedBox.shrink(),
      builder: (context, data) {
        final status = data[0] as Json;
        final list = data[1] as List<Json>;
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
                    ? 'Pay with ${Channel.parse(status.s('gateway')).name} into your group\'s own account. '
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
                          final r = await showPaymentDialog(context, online: true);
                          if (r == null) return;
                          _justStarted = r.s('id');
                          if (!context.mounted) return;
                          await _open(r.s('checkout_url'));
                          await st.refresh();
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
                            child: Text('${Purpose.labelOf(p.s('purpose'))} • ${money(context, p.i('amount'))} • ${p.s('member_name')}',
                                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          StatusPill(p.s('status')),
                        ]),
                        Text(
                          '${Dates.dayTime(p['created_at'])} • Ref ${p.s('tx_ref')}'
                          '${p.n('gateway_tx_id') != null ? ' • ${Channel.parse(p.s('gateway')).name} ID ${p.s('gateway_tx_id')}' : ''}'
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

/// Group Settings: connect the group's OWN gateway account. Admin or treasurer only.
/// Keys go to our server, which tests them with the gateway and locks them. Nobody can read them back.
class GatewaySetupCard extends StatefulWidget {
  const GatewaySetupCard({super.key});
  @override
  State<GatewaySetupCard> createState() => _GatewaySetupCardState();
}

class _GatewaySetupCardState extends State<GatewaySetupCard> {
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
    final keys = gateway == 'flutterwave'
        ? {'secret_key': k1.text.trim(), 'webhook_hash': k2.text.trim()}
        : {'consumer_key': k1.text.trim(), 'consumer_secret': k2.text.trim()};
    final ok = await runAndTell(context, () async {
      final r = await st.api.saveGatewayKeys(st.orgId, gateway: gateway, mode: mode, keys: keys);
      webhookUrl = r.n('webhook_url');
    }, done: 'Connected. The keys worked and are now locked on the server.');
    if (!mounted) return;
    setState(() {
      busy = false;
      if (ok) {
        k1.clear();
        k2.clear();
        editing = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final isDemo = st.org!.b('is_demo');
    if (!isDemo && mode == 'test') mode = 'live';
    // If the status cannot be read, the card still shows, so keys can still be connected.
    return Loaded<Json>(
      load: () => st.api.gatewayStatus(st.orgId),
      waiting: const SizedBox.shrink(),
      error: (e) => _card(context, st, const {}, isDemo, error: e),
      builder: (context, s) => _card(context, st, s, isDemo),
    );
  }

  Widget _card(BuildContext context, AppState st, Json s, bool isDemo, {Object? error}) {
    final tt = Theme.of(context).textTheme;
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
          if (error != null) Text(error.toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (s.b('enabled'))
            Text(
              'Connected: ${Channel.parse(s.s('gateway')).name} • ${s.s('mode') == 'test' ? 'TEST money' : 'LIVE'} • key ending ${s.s('key_hint')}\n'
              'By ${s.s('updated_by')} on ${Dates.dayTime(s['updated_at'])}',
              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            )
          else
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
                  onPressed: () => runAndTell(context, () => st.api.disableGateway(st.orgId), done: 'Online payments switched off.'),
                  child: const Text('Switch off'),
                ),
            ]),
          ] else ...[
            gap,
            DropdownButtonFormField<String>(
              initialValue: gateway,
              decoration: InputDecoration(labelText: 'Gateway'),
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
              decoration: InputDecoration(labelText: 'Money'),
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
  }
}
