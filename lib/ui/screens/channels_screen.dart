import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../theme.dart';
import '../widgets.dart';

/// Money moves on MTN, Airtel, bank or cash, into the group's OWN account.
/// This screen helps dial, then records the transaction ID. It never touches the money.
class ChannelsScreen extends StatelessWidget {
  const ChannelsScreen({super.key});

  Future<void> dial(BuildContext context, String code) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse('tel:${code.replaceAll('#', '%23')}'));
    } catch (_) {}
    if (!opened && context.mounted) {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) showMsg(context, 'Phone could not open the dialer. Code copied: dial $code yourself.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final org = st.org!;
    return AppPageView(children: [
      SaccoCard(
        color: cs.secondaryContainer,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mobile Channels', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSecondaryContainer)),
          const SizedBox(height: 6),
          Text(
              '1. Pay your group\'s own account on your phone.\n2. Copy the transaction ID from the SMS.\n3. Record it here. A second person checks it, then it joins the ledger.\n\nThe app never holds your money.',
              style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer)),
        ]),
      ),
      SaccoCard(
        elevation: 2,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.dialpad, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Open mobile money', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
          ]),
          gap,
          Row(children: [
            Expanded(child: FilledButton(onPressed: () => dial(context, '*165#'), child: const Text('MTN *165#'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.tonal(onPressed: () => dial(context, '*185#'), child: const Text('Airtel *185#'))),
          ]),
          if (org.n('mtn_merchant_code') != null) ...[gap, Text('MTN pay to: ${org.s('mtn_merchant_code')}', style: tt.bodySmall)],
          if (org.n('airtel_merchant_code') != null) ...[gap, Text('Airtel pay to: ${org.s('airtel_merchant_code')}', style: tt.bodySmall)],
        ]),
      ),
      FilledButton.icon(
        onPressed: st.myMemberId == null ? null : () => showRecordPayment(context),
        icon: const Icon(Icons.edit_note),
        label: const Text('Record a Payment'),
      ),
      if (st.outbox.isNotEmpty)
        Align(
            alignment: Alignment.centerLeft,
            child: Pill(text: '${st.outbox.length} record(s) waiting for signal. They send by themselves.', color: warnOrange)),
      for (final f in st.outboxFailures) Text('Not accepted: $f', style: TextStyle(color: cs.error)),
      SectionTitle(st.isOfficer ? 'Latest Payment Records' : 'My Payment Records'),
      if (st.payments.isEmpty) const EmptyNote('No payment records yet.'),
      for (final p in st.payments.take(30)) PaymentTile(p),
    ]);
  }
}

class PaymentTile extends StatelessWidget {
  final Json p;
  final List<Widget> actions;
  const PaymentTile(this.p, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SaccoCard(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('${purposeNames[p.s('purpose')]} • ${money(context, p.i('amount'))}',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary))),
          StatusPill(p.s('status')),
        ]),
        const SizedBox(height: 4),
        Text('${p.n('member_name') ?? 'Group'} • ${channelNames[p.s('channel')]}${p.n('external_ref') != null ? ' • ID ${p.s('external_ref')}' : ''}',
            style: tt.bodySmall),
        Text('Recorded by ${p.s('submitted_by_name')} • ${Dates.dayTime(p['submitted_at'])}', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        if (p.n('reviewed_by_name') != null)
          Text('Checked by ${p.s('reviewed_by_name')}${p.n('review_note') != null ? ': ${p.s('review_note')}' : ''}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        if (p.n('note') != null) Text(p.s('note'), style: tt.labelSmall),
        if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)),
      ]),
    );
  }
}

Future<void> showRecordPayment(BuildContext context, {String purpose = 'shares', String channel = 'mtn_momo', String? loanId, String? memberId}) async {
  await showDialog(context: context, builder: (_) => _RecordPaymentDialog(purpose, channel, loanId, memberId));
}

class _RecordPaymentDialog extends StatefulWidget {
  final String purpose;
  final String channel;
  final String? loanId;
  final String? memberId;
  const _RecordPaymentDialog(this.purpose, this.channel, this.loanId, this.memberId);
  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late String purpose = widget.purpose;
  late String channel = widget.channel;
  late String? loanId = widget.loanId;
  String? memberId;
  final amount = TextEditingController();
  final shares = TextEditingController(text: '1');
  final ref = TextEditingController();
  final note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    memberId ??= widget.memberId ?? st.myMemberId;
    final price = st.org!.i('share_price');
    final count = int.tryParse(shares.text.trim()) ?? 0;
    final purposes = [
      'shares',
      'savings',
      'fine',
      'loan_repayment',
      'emergency_contribution',
      if (st.canReview) ...['withdrawal', 'expense'],
    ];
    final memberLoans = st.loans.where((l) => l.s('member_id') == memberId && l.s('status') == 'active').toList();
    if (!memberLoans.any((l) => l.s('id') == loanId)) loanId = memberLoans.isEmpty ? null : memberLoans.first.s('id');

    return FormDialog(
      title: 'Record a Payment',
      confirm: 'Record',
      fields: (ctx, _) => [
        DropdownButtonFormField<String>(
          initialValue: purpose,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'What is it for?'),
          items: [for (final p in purposes) DropdownMenuItem(value: p, child: Text(purposeNames[p]!))],
          onChanged: (v) => setState(() => purpose = v ?? purpose),
        ),
        if (purpose != 'expense' && st.canRecordForOthers)
          MemberPicker(label: 'Member', value: memberId, members: st.activeMembers, onChanged: (v) => setState(() => memberId = v)),
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
                      DropdownMenuItem(value: l.s('id'), child: Text('${l.s('loan_number')} • left ${money(context, l.i('remaining'))}'))
                  ],
                  onChanged: (v) => setState(() => loanId = v),
                ),
        if (purpose == 'shares') ...[
          TextField(
              controller: shares,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Number of shares (${money(context, price)} each)'),
              onChanged: (_) => setState(() {})),
          Text('Total: ${money(context, count * price)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ] else
          MoneyField(controller: amount, label: 'Amount', currency: st.currency),
        ChannelPicker(value: channel, onChanged: (v) => setState(() => channel = v)),
        if (channel != 'cash')
          TextField(
              controller: ref, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Transaction ID from the SMS')),
        if (purpose == 'fine' || purpose == 'expense' || purpose == 'withdrawal')
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Reason')),
      ],
      onConfirm: (ctx) async {
        final nav = Navigator.of(ctx);
        final messenger = ScaffoldMessenger.of(nav.context);
        final value = purpose == 'shares' ? count * price : Money.parse(amount.text, st.currency);
        if (value == null || value <= 0) {
          showMsg(ctx, 'Enter a valid amount.', error: true);
          return;
        }
        if (channel != 'cash' && ref.text.trim().isEmpty) {
          showMsg(ctx, 'Enter the transaction ID.', error: true);
          return;
        }
        final err = await st.recordPayment(
          memberId: purpose == 'expense' ? null : memberId,
          purpose: purpose,
          amount: value,
          channel: channel,
          ref: channel == 'cash' ? null : ref.text.trim(),
          loanId: purpose == 'loan_repayment' ? loanId : null,
          note: note.text.trim(),
        );
        if (err == null || err == 'queued') {
          nav.pop();
          messenger.showSnackBar(SnackBar(content: Text(err == 'queued' ? 'No signal: saved. It will send when you are online.' : 'Recorded.')));
        } else if (ctx.mounted) {
          showMsg(ctx, err, error: true);
        }
      },
    );
  }
}
