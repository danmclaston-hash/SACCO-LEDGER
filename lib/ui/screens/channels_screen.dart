import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/config.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../theme.dart';
import '../widgets.dart';
import 'online_pay.dart';
import '../text.dart';

/// Money moves on MTN, Airtel, bank or cash, into the group's OWN account.
/// This screen helps dial, then records the transaction ID. It never touches the money.
class ChannelsScreen extends StatelessWidget {
  const ChannelsScreen({super.key});

  Future<void> dial(BuildContext context, String code) => openOrCopy(context, Uri.parse('tel:${code.replaceAll('#', '%23')}'),
      copy: code, failMessage: 'Phone could not open the dialer. Code copied: dial $code yourself.');

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final org = st.org!;
    return AppPageView(
      children: [
        SaccoCard(
          color: cs.secondaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mobile Channels',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSecondaryContainer),
              ),
              const SizedBox(height: 6),
              Text(
                '1. Pay your group\'s own account on your phone.\n2. Copy the transaction ID from the SMS.\n3. Record it here. A second person checks it, then it joins the ledger.\n\nThe app never holds your money.',
                style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer),
              ),
            ],
          ),
        ),
        SaccoCard(
          elevation: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.dialpad, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Open mobile money', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              gap,
              Row(
                children: [
                  Expanded(child: BrandButton(channel: 'mtn_momo', label: 'MTN *165#', onPressed: () => dial(context, '*165#'))),
                  const SizedBox(width: 8),
                  Expanded(child: BrandButton(channel: 'airtel_money', label: 'Airtel *185#', onPressed: () => dial(context, '*185#'))),
                ],
              ),
              if (org.n('mtn_merchant_code') != null) ...[gap, Text('MTN pay to: ${org.s('mtn_merchant_code')}', style: tt.bodySmall)],
              if (org.n('airtel_merchant_code') != null) ...[gap, Text('Airtel pay to: ${org.s('airtel_merchant_code')}', style: tt.bodySmall)],
            ],
          ),
        ),
        if (AppConfig.onlinePayments) const OnlinePayCard(),
        FilledButton.icon(
          onPressed: st.myMemberId == null ? null : () => showPaymentDialog(context),
          icon: const Icon(Icons.edit_note),
          label: const Text('Record a Payment'),
        ),
        if (st.outbox.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Pill(text: '${st.outbox.length} record(s) waiting for signal. They send by themselves.', color: warnOrange),
          ),
        for (final f in st.outboxFailures) Text('Not accepted: $f', style: TextStyle(color: cs.error)),
        SectionTitle(st.role.isOfficer ? 'Latest Payment Records' : 'My Payment Records', info: 'two_person'),
        if (st.payments.isEmpty) const EmptyNote('No payment records yet.'),
        for (final p in st.payments.take(30)) PaymentTile(p),
      ],
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Purpose.labelOf(p.s('purpose'))} • ${money(context, p.i('amount'))}',
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                ),
              ),
              StatusPill(p.s('status')),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
            BrandChip(p.s('channel')),
            Text('${p.n('member_name') ?? 'Group'}${p.n('external_ref') != null ? ' • ID ${p.s('external_ref')}' : ''}', style: tt.bodySmall),
          ]),
          Text('Recorded by ${p.s('submitted_by_name')} • ${Dates.dayTime(p['submitted_at'])}', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          if (p.n('reviewed_by_name') != null)
            Text(
              'Checked by ${p.s('reviewed_by_name')}${p.n('review_note') != null ? ': ${p.s('review_note')}' : ''}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          if (p.n('goal_id') != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                ExcludeSemantics(child: Icon(Icons.flag, size: 14, color: cs.primary)),
                const SizedBox(width: 4),
                Flexible(
                    child: Text('For goal: ${StateScope.of(context).goalName(p.n('goal_id')) ?? 'a goal'}',
                        style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
              ]),
            ),
          if (p.n('note') != null) Text(p.s('note'), style: tt.labelSmall),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ),
        ],
      ),
    );
  }
}

/// Records a payment made by hand. With [online], starts a checked online payment instead and
/// returns {id, tx_ref, checkout_url}. The questions are the same either way.
Future<Json?> showPaymentDialog(BuildContext context,
        {bool online = false, Purpose? purpose, Channel channel = Channel.mtnMomo, String? loanId, String? memberId, String? goalId}) =>
    showDialog<Json>(
      context: context,
      builder: (_) => _PaymentDialog(online, purpose ?? (online ? Purpose.savings : Purpose.shares), channel, loanId, memberId, goalId),
    );

class _PaymentDialog extends StatefulWidget {
  final bool online;
  final Purpose purpose;
  final Channel channel;
  final String? loanId;
  final String? memberId;
  final String? goalId;
  const _PaymentDialog(this.online, this.purpose, this.channel, this.loanId, this.memberId, this.goalId);
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late Purpose purpose = widget.purpose;
  late Channel channel = widget.channel;
  late String? loanId = widget.loanId;
  late String? goalId = widget.goalId;
  String? memberId;
  final amount = TextEditingController();
  final shares = TextEditingController(text: '1');
  final ref = TextEditingController();
  final note = TextEditingController();

  @override
  void dispose() {
    for (final c in [amount, shares, ref, note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final online = widget.online;
    memberId ??= widget.memberId ?? st.myMemberId;
    final price = st.org!.i('share_price');
    final count = int.tryParse(shares.text.trim()) ?? 0;
    final memberLoans = st.loans.where((l) => l.s('member_id') == memberId && l.s('status') == 'active').toList();
    if (!memberLoans.any((l) => l.s('id') == loanId)) loanId = memberLoans.firstOrNull?.s('id');

    return FormDialog(
      title: online ? 'Pay online' : 'Record a Payment',
      confirm: online ? 'Go to payment' : 'Record',
      fields: (ctx, _) => [
        DropdownButtonFormField<Purpose>(
          initialValue: purpose,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'What is it for?'),
          items: [
            for (final p in Purpose.choices(handlesMoney: st.role.handlesMoney, online: online)) DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (v) => setState(() => purpose = v ?? purpose),
        ),
        if (purpose.forMember && st.role.canRunMeetings)
          MemberPicker(label: 'Member', value: memberId, members: st.activeMembers, onChanged: (v) => setState(() => memberId = v)),
        if (purpose.takesLoan)
          memberLoans.isEmpty
              ? const EmptyNote('This member has no active loan.')
              : DropdownButtonFormField<String>(
                  key: ValueKey(memberId),
                  initialValue: loanId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Loan'),
                  items: [
                    for (final l in memberLoans)
                      DropdownMenuItem(value: l.s('id'), child: Text('${l.s('loan_number')} • left ${money(context, l.i('remaining'))}')),
                  ],
                  onChanged: (v) => setState(() => loanId = v),
                ),
        if (purpose == Purpose.shares) ...[
          TextField(
            controller: shares,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Number of shares (${money(context, price)} each)'),
            onChanged: (_) => setState(() {}),
          ),
          Text('Total: ${money(context, count * price)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ] else
          MoneyField(controller: amount, label: 'Amount', currency: st.currency),
        if (purpose.takesGoal && st.activeGoals.isNotEmpty)
          GoalPicker(label: 'Is this for a goal?', value: goalId, goals: st.activeGoals, onChanged: (v) => setState(() => goalId = v)),
        if (online)
          const EmptyNote('Next: a secure payment page opens. Pay there with mobile money or card. Then come back here.')
        else ...[
          ChannelFields(value: channel, ref: ref, onChanged: (v) => setState(() => channel = v)),
          if (purpose.needsReason) TextField(controller: note, decoration: InputDecoration(labelText: 'Reason')),
        ],
      ],
      onConfirm: (ctx) async {
        final nav = Navigator.of(ctx);
        final messenger = ScaffoldMessenger.of(nav.context);
        final value = purpose == Purpose.shares ? count * price : Money.parse(amount.text, st.currency);
        final loan = purpose.takesLoan ? loanId : null;
        final goal = purpose.takesGoal ? goalId : null;
        if (value == null || value <= 0) return showMsg(ctx, 'Enter a valid amount.', error: true);
        if (purpose.takesLoan && loan == null) return showMsg(ctx, 'Choose a loan.', error: true);
        if (online) {
          try {
            nav.pop(await st.api.startOnlinePayment(st.orgId, memberId: memberId!, purpose: purpose.code, amount: value, loanId: loan, goalId: goal));
          } catch (e) {
            if (ctx.mounted) showMsg(ctx, e.toString(), error: true);
          }
          return;
        }
        final refProblem = ChannelFields.problem(channel, ref);
        if (refProblem != null) return showMsg(ctx, refProblem, error: true);
        final r = await st.recordPayment(
          memberId: purpose.forMember ? memberId : null,
          purpose: purpose.code,
          amount: value,
          channel: channel.code,
          ref: ChannelFields.refFor(channel, ref),
          loanId: loan,
          goalId: goal,
          note: note.text.trim(),
        );
        if (r.error == null) {
          nav.pop();
          messenger.showSnackBar(SnackBar(content: Text(r.queued ? 'No signal: saved. It will send when you are online.' : 'Recorded.')));
        } else if (ctx.mounted) {
          showMsg(ctx, r.error!, error: true);
        }
      },
    );
  }
}
