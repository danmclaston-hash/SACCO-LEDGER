import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/loan_math.dart';
import '../../core/money.dart';
import '../../core/risk.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels_screen.dart';
import 'loan_calculator.dart';
import '../text.dart';

class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final org = st.org!;
    final active = st.loans.where((l) => l.s('status') == 'active').toList();
    int band(String b) => active.where((l) => arrearsBand(l.i('arrears_days')) == b).length;

    return AppPageView(
      children: [
        SaccoCard(
          color: cs.primaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Still owed on loans', style: tt.bodySmall),
                      Text(money(context, active.fold<int>(0, (a, l) => a + l.i('remaining'))), style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Most a member can borrow', style: tt.bodySmall),
                      Text(
                        '${org.i('max_loan_multiplier')}× their savings',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(describeInterest(LoanTerms.fromGroup(org)), style: tt.bodySmall),
              Text(describeLateFee(LoanTerms.fromGroup(org), (v) => money(context, v)), style: tt.bodySmall),
              gap,
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoanCalculatorScreen())),
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Calculator'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: st.myMemberId == null ? null : () => _apply(context, st),
                    icon: const Icon(Icons.add),
                    label: const Text('Apply'),
                  ),
                ),
              ]),
            ],
          ),
        ),
        if (active.any((l) => l.i('arrears_days') > 0))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Late loans', info: 'arrears'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Band('On time', band('Current'), okGreen),
                  _Band('1-30 days late', band('Watch'), saccoGold),
                  _Band('31-60 days late', band('Substandard'), warnOrange),
                  _Band('Over 60 days', band('Doubtful') + band('Loss'), cs.error),
                ],
              ),
            ],
          ),
        SectionTitle('All loans (${st.loans.length})'),
        if (st.loans.isEmpty) const EmptyNote('No loans recorded yet.'),
        for (final l in st.loans) _LoanCard(l),
      ],
    );
  }

  void _apply(BuildContext context, AppState st) {
    final principal = TextEditingController();
    final term = TextEditingController(text: '3');
    final purpose = TextEditingController();
    String? member = st.myMemberId;
    final group = LoanTerms.fromGroup(st.org!);
    var terms = group;
    var custom = false;
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Ask for a loan',
        confirm: 'Send request',
        fields: (ctx, set) {
          final m = st.members.where((x) => x.s('id') == member);
          final savings = m.isEmpty ? 0 : m.first.i('savings');
          return [
            if (st.role.canApplyForOthers) MemberPicker(label: 'Borrower', value: member, members: st.activeMembers, onChanged: (v) => set(() => member = v)),
            Text(
              'Savings ${Money.format(savings, st.currency)}. Limit ${Money.format(savings * st.org!.i('max_loan_multiplier'), st.currency)}, less current loans.',
            ),
            MoneyField(controller: principal, label: 'Principal Amount', currency: st.currency, onChanged: (_) => set(() {})),
            TextField(
              controller: term,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Term (Months)'),
              onChanged: (_) => set(() {}),
            ),
            TextField(
              controller: purpose,
              decoration: InputDecoration(labelText: 'What is the loan for?'),
            ),
            LoanSummary(
              principal: Money.parse(principal.text, st.currency) ?? 0,
              term: (int.tryParse(term.text.trim()) ?? 0).clamp(0, 60),
              terms: custom ? terms : group,
              currency: st.currency,
              start: Dates.today(),
              showSchedule: true,
            ),
            if (st.role.canApproveLoans) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: custom,
                onChanged: (v) => set(() => custom = v),
                title: const Text('Different rules for this loan'),
                subtitle: const Text('Only the admin or loan officer. Shown to the committee and kept in the audit trail.'),
              ),
              if (custom) LoanRulesEditor(value: terms, currency: st.currency, onChanged: (v) => set(() => terms = v)),
            ],
          ];
        },
        onConfirm: (ctx) async {
          final p = Money.parse(principal.text, st.currency);
          final t = int.tryParse(term.text.trim());
          if (p == null || t == null || t < 1 || t > 60 || member == null) {
            showMsg(ctx, 'Enter amount and term (1 to 60 months).', error: true);
            return;
          }
          await runAndClose(ctx, () => st.api.applyLoan(st.orgId, member!, p, t, custom ? terms.toJson() : null, purpose.text),
              done: 'Application sent for approval.');
        },
      ),
    );
  }
}

class _Band extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Band(this.label, this.count, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SaccoCard(
            radius: 12,
            padding: const EdgeInsets.all(8),
            color: color.withValues(alpha: 0.12),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
                ),
                Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      );
}

class _LoanCard extends StatelessWidget {
  final Json l;
  const _LoanCard(this.l);

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = l.s('status');
    final remaining = l.i('remaining');
    final arrears = l.i('arrears_days');
    return SaccoCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.s('loan_number')} • ${l.s('borrower')}', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      l.i('schedule_version') == 2
                          ? 'Principal: ${money(context, l.i('principal'))} • ${l.i('term_months')} mo • ${l.s('repayment_plan') == 'end' ? 'all at the end' : 'monthly'}\n'
                              '${describeInterest(LoanTerms.fromLoan(l))} ${describeLateFee(LoanTerms.fromLoan(l), (v) => money(context, v))}'
                          : 'Principal: ${money(context, l.i('principal'))} @ ${l.i('interest_rate_pct')}% a year • ${l.i('term_months')} mo • ${l.s('calculation_type').replaceAll('_', ' ')}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (l.n('purpose') != null) Text(l.s('purpose'), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (l.n('approver_name') != null)
                      Text(
                        'Approved by ${l.s('approver_name')} (${l.s('resolution_ref')}). Witnesses: ${l.s('witness1_name')}, ${l.s('witness2_name')}',
                        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    if (arrears > 0)
                      Text(
                        '$arrears days late (${arrearsBand(arrears)})',
                        style: tt.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
                      ),
                    if (l.n('rejected_reason') != null) Text('Rejected: ${l.s('rejected_reason')}', style: tt.labelSmall?.copyWith(color: cs.error)),
                  ],
                ),
              ),
              StatusPill(status),
            ],
          ),
          const SizedBox(height: 8),
          if (status == 'active' || status == 'paid')
            Text(
              'Remaining Balance: ${money(context, remaining)}',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
            ),
          if (status == 'active' && l['next_due'] is Map)
            Text(
              'Next: ${money(context, l.m('next_due').i('amount'))} by ${Dates.day(l.m('next_due')['date'])}',
              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (l.i('late_fees_due') > 0)
            Text(
              'Late fees owed now: ${money(context, l.i('late_fees_due'))} (included above)',
              style: tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: () => _schedule(context, st), child: const Text('Schedule')),
              if (l.s('late_fee_type') != 'none' && (status == 'active' || status == 'paid'))
                TextButton(onPressed: () => _lateFees(context, st), child: const Text('Late fees')),
              if (status == 'pending_approval' && st.role.canApproveLoans) ...[
                OutlinedButton(onPressed: () => _reject(context, st), child: const Text('Reject')),
                FilledButton(onPressed: () => _approve(context, st), child: const Text('Approve')),
              ],
              if (status == 'approved' && st.role.handlesMoney) FilledButton(onPressed: () => _disburse(context, st), child: const Text('Disburse')),
              if (status == 'active' && st.myMemberId != null && (st.role.canRunMeetings || l.s('member_id') == st.myMemberId))
                FilledButton.tonal(
                  onPressed: () => showPaymentDialog(context, purpose: Purpose.loanRepayment, loanId: l.s('id'), memberId: l.s('member_id')),
                  child: const Text('Repay'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reject(BuildContext context, AppState st) async {
    final r = await askText(context, title: 'Reject loan', label: 'Why?', confirm: 'Reject');
    if (r == null || !context.mounted) return;
    await runAndTell(context, () => st.api.rejectLoan(l.s('id'), r));
  }

  void _approve(BuildContext context, AppState st) {
    final res = TextEditingController();
    String? w1;
    String? w2;
    final others = st.activeMembers.where((m) => m.s('id') != l.s('member_id')).toList();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Committee Loan Approval',
        confirm: 'Confirm Approval',
        fields: (ctx, set) => [
          Text('${l.s('borrower')}: ${Money.format(l.i('principal'), st.currency)}'),
          TextField(
            controller: res,
            decoration: InputDecoration(labelText: 'Resolution Reference'),
          ),
          MemberPicker(label: 'Witness 1 (Non-borrower)', value: w1, members: others, onChanged: (v) => set(() => w1 = v)),
          MemberPicker(label: 'Witness 2 (Non-borrower)', value: w2, members: others, onChanged: (v) => set(() => w2 = v)),
        ],
        onConfirm: (ctx) async {
          if (w1 == null || w2 == null) {
            showMsg(ctx, 'Choose two witnesses.', error: true);
            return;
          }
          await runAndClose(ctx, () => st.api.approveLoan(l.s('id'), res.text, w1!, w2!), done: 'Loan approved. A different officer pays it out.');
        },
      ),
    );
  }

  void _disburse(BuildContext context, AppState st) {
    var channel = Channel.cash;
    final ref = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Record Loan Pay-out',
        confirm: 'Record Pay-out',
        fields: (ctx, set) => [
          Text('Pay ${Money.format(l.i('principal'), st.currency)} to ${l.s('borrower')} from the group\'s own money, then record it here.'),
          ChannelFields(value: channel, ref: ref, onChanged: (v) => set(() => channel = v)),
        ],
        onConfirm: (ctx) async {
          final problem = ChannelFields.problem(channel, ref);
          if (problem != null) return showMsg(ctx, problem, error: true);
          await runAndClose(ctx, () => st.api.disburseLoan(l.s('id'), channel.code, ChannelFields.refFor(channel, ref)), done: 'Pay-out recorded.');
        },
      ),
    );
  }

  /// Every late payment, how late, and the fee. Admin or treasurer can forgive (not their own).
  Future<void> _lateFees(BuildContext context, AppState st) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Late fees ${l.s('loan_number')}'),
        content: SizedBox(
          width: 460,
          child: Loaded<Json>(
            load: () => st.api.lateFeeReport(l.s('id')),
            builder: (c, r) {
              final tt = Theme.of(c).textTheme;
              return SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text(describeLateFee(LoanTerms.fromLoan(l), (v) => Money.format(v, st.currency)), style: tt.bodySmall),
                  const Divider(),
                  if (r.l('rows').isEmpty) const EmptyNote('No late payments. Well done.'),
                  for (final x in r.l('rows'))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Payment ${x.i('installment')} (${Money.format(x.i('amount_due'), st.currency)}) due ${Dates.day(x['due_date'])}: '
                        '${x.i('days_late')} days late${x.n('paid_on') != null ? ', paid ${Dates.day(x['paid_on'])}' : ', still unpaid'} → '
                        '${Money.format(x.i('fee'), st.currency)}',
                        style: tt.bodySmall,
                      ),
                    ),
                  const Divider(),
                  Text('Total late fees: ${Money.format(r.i('total'), st.currency)}${r.b('capped') ? ' (limit reached)' : ''}'),
                  Text('Paid: ${Money.format(r.i('paid'), st.currency)} • Forgiven: ${Money.format(r.i('waived'), st.currency)}'),
                  Text('Owed now: ${Money.format(r.i('due'), st.currency)}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  for (final w in r.l('waivers'))
                    Text('Forgiven ${Money.format(w.i('amount'), st.currency)} by ${w.s('by')}: ${w.s('reason')}', style: tt.labelSmall),
                ]),
              );
            },
          ),
        ),
        actions: [
          if (st.role.handlesMoney && l.s('member_id') != st.myMemberId && l.i('late_fees_due') > 0)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _forgive(context, st);
              },
              child: const Text('Forgive'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _forgive(BuildContext context, AppState st) async {
    final amount = TextEditingController(text: Money.plain(l.i('late_fees_due'), st.currency));
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Forgive late fees',
        confirm: 'Forgive',
        fields: (ctx, set) => [
          Text('Owed now: ${Money.format(l.i('late_fees_due'), st.currency)}. This is permanent and shown in the audit trail.'),
          MoneyField(controller: amount, label: 'Amount to forgive', currency: st.currency),
          TextField(controller: reason, decoration: InputDecoration(labelText: 'Why? (e.g. agreed in meeting 12)')),
        ],
        onConfirm: (ctx) async {
          final a = Money.parse(amount.text, st.currency);
          if (a == null) {
            showMsg(ctx, 'Enter a valid amount.', error: true);
            return;
          }
          await runAndClose(ctx, () => st.api.waiveLateFees(l.s('id'), a, reason.text), done: 'Late fees forgiven.');
        },
      ),
    );
  }

  Future<void> _schedule(BuildContext context, AppState st) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Schedule ${l.s('loan_number')}'),
        content: SizedBox(
          width: 460,
          child: Loaded<List<Json>>(
            load: () => st.api.loanSchedule(l.s('id')),
            builder: (c, rows) {
              return SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 12,
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Due')),
                    DataColumn(label: Text('Pay'), numeric: true),
                    DataColumn(label: Text('Left'), numeric: true),
                  ],
                  rows: [
                    for (final s in rows)
                      DataRow(
                        cells: [
                          DataCell(Text('${s.i('installment')}')),
                          DataCell(Text(Dates.day(s['due_date']))),
                          DataCell(Text(Money.format(s.i('total_due'), st.currency))),
                          DataCell(Text(Money.format(s.i('ending_balance'), st.currency))),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
