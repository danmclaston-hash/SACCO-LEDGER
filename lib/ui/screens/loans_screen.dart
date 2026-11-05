import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/risk.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels_screen.dart';

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

    return AppPageView(children: [
      SaccoCard(
        color: cs.primaryContainer,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Active Portfolio', style: tt.labelSmall),
              Text(money(context, active.fold<int>(0, (a, l) => a + l.i('remaining'))), style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Policy Limit', style: tt.labelSmall),
              Text('${org.i('max_loan_multiplier')}x Savings @ ${org.i('default_interest_rate_pct')}%',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ]),
          gap,
          FilledButton.icon(
              onPressed: st.myMemberId == null ? null : () => _apply(context, st), icon: const Icon(Icons.add), label: const Text('Apply for New Loan')),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Arrears Aging Classification'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Band('Current', band('Current'), okGreen),
          _Band('Watch (1-30d)', band('Watch'), saccoGold),
          _Band('Substandard (31-60d)', band('Substandard'), warnOrange),
          _Band('Doubtful / Loss (61d+)', band('Doubtful') + band('Loss'), cs.error),
        ]),
      ]),
      const SectionTitle('Loan Directory'),
      if (st.loans.isEmpty) const EmptyNote('No loans recorded yet.'),
      for (final l in st.loans) _LoanCard(l),
    ]);
  }

  void _apply(BuildContext context, AppState st) {
    final principal = TextEditingController();
    final term = TextEditingController(text: '3');
    final purpose = TextEditingController();
    String? member = st.myMemberId;
    var type = 'flat';
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Request Loan Application',
        confirm: 'Submit Application',
        fields: (ctx, set) {
          final m = st.members.where((x) => x.s('id') == member);
          final savings = m.isEmpty ? 0 : m.first.i('savings');
          return [
            if (st.canApplyForOthers) MemberPicker(label: 'Borrower', value: member, members: st.activeMembers, onChanged: (v) => set(() => member = v)),
            Text(
                'Savings ${Money.format(savings, st.currency)}. Limit ${Money.format(savings * st.org!.i('max_loan_multiplier'), st.currency)}, less current loans.'),
            MoneyField(controller: principal, label: 'Principal Amount', currency: st.currency),
            TextField(controller: term, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Term (Months)')),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Interest method'),
              items: const [DropdownMenuItem(value: 'flat', child: Text('Flat')), DropdownMenuItem(value: 'reducing_balance', child: Text('Reducing balance'))],
              onChanged: (v) => set(() => type = v ?? type),
            ),
            TextField(controller: purpose, decoration: const InputDecoration(labelText: 'What is the loan for?')),
          ];
        },
        onConfirm: (ctx) async {
          final p = Money.parse(principal.text, st.currency);
          final t = int.tryParse(term.text.trim());
          if (p == null || t == null || t < 1 || t > 60 || member == null) {
            showMsg(ctx, 'Enter amount and term (1 to 60 months).', error: true);
            return;
          }
          await runAndClose(ctx, st, () => st.api.applyLoan(st.orgId, member!, p, t, type, purpose.text), done: 'Application sent for approval.');
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
            child: Column(children: [
              Text('$count', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
            ]),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${l.s('loan_number')} • ${l.s('borrower')}', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                  'Principal: ${money(context, l.i('principal'))} @ ${l.i('interest_rate_pct')}% • ${l.i('term_months')} mo • ${l.s('calculation_type').replaceAll('_', ' ')}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if (l.n('purpose') != null) Text(l.s('purpose'), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if (l.n('approver_name') != null)
                Text('Approved by ${l.s('approver_name')} (${l.s('resolution_ref')}). Witnesses: ${l.s('witness1_name')}, ${l.s('witness2_name')}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              if (arrears > 0)
                Text('$arrears days late (${arrearsBand(arrears)})', style: tt.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold)),
              if (l.n('rejected_reason') != null) Text('Rejected: ${l.s('rejected_reason')}', style: tt.labelSmall?.copyWith(color: cs.error)),
            ]),
          ),
          StatusPill(status),
        ]),
        const SizedBox(height: 8),
        if (status == 'active' || status == 'paid')
          Text('Remaining Balance: ${money(context, remaining)}', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: () => _schedule(context, st), child: const Text('Schedule')),
          if (status == 'pending_approval' && st.canApproveLoans) ...[
            OutlinedButton(onPressed: () => _reject(context, st), child: const Text('Reject')),
            FilledButton(onPressed: () => _approve(context, st), child: const Text('Approve')),
          ],
          if (status == 'approved' && st.canDisburse) FilledButton(onPressed: () => _disburse(context, st), child: const Text('Disburse')),
          if (status == 'active' && st.myMemberId != null && (st.canRecordForOthers || l.s('member_id') == st.myMemberId))
            FilledButton.tonal(
                onPressed: () => showRecordPayment(context, purpose: 'loan_repayment', loanId: l.s('id'), memberId: l.s('member_id')),
                child: const Text('Repay')),
        ]),
      ]),
    );
  }

  Future<void> _reject(BuildContext context, AppState st) async {
    final r = await askText(context, title: 'Reject loan', label: 'Why?', confirm: 'Reject');
    if (r == null) return;
    final err = await st.act(() => st.api.rejectLoan(l.s('id'), r));
    if (err != null && context.mounted) showMsg(context, err, error: true);
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
          TextField(controller: res, decoration: const InputDecoration(labelText: 'Resolution Reference')),
          MemberPicker(label: 'Witness 1 (Non-borrower)', value: w1, members: others, onChanged: (v) => set(() => w1 = v)),
          MemberPicker(label: 'Witness 2 (Non-borrower)', value: w2, members: others, onChanged: (v) => set(() => w2 = v)),
        ],
        onConfirm: (ctx) async {
          if (w1 == null || w2 == null) {
            showMsg(ctx, 'Choose two witnesses.', error: true);
            return;
          }
          await runAndClose(ctx, st, () => st.api.approveLoan(l.s('id'), res.text, w1!, w2!), done: 'Loan approved. A different officer pays it out.');
        },
      ),
    );
  }

  void _disburse(BuildContext context, AppState st) {
    var channel = 'cash';
    final ref = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Record Loan Pay-out',
        confirm: 'Record Pay-out',
        fields: (ctx, set) => [
          Text('Pay ${Money.format(l.i('principal'), st.currency)} to ${l.s('borrower')} from the group\'s own money, then record it here.'),
          ChannelPicker(value: channel, onChanged: (v) => set(() => channel = v)),
          if (channel != 'cash') TextField(controller: ref, decoration: const InputDecoration(labelText: 'Transaction ID')),
        ],
        onConfirm: (ctx) => runAndClose(ctx, st, () => st.api.disburseLoan(l.s('id'), channel, ref.text), done: 'Pay-out recorded.'),
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
          child: FutureBuilder<List<Json>>(
            future: st.api.loanSchedule(l.s('id')),
            builder: (c, snap) {
              if (snap.hasError) return Text(snap.error.toString());
              if (!snap.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
              return SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 12,
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Due')),
                    DataColumn(label: Text('Pay'), numeric: true),
                    DataColumn(label: Text('Left'), numeric: true)
                  ],
                  rows: [
                    for (final s in snap.data!)
                      DataRow(cells: [
                        DataCell(Text('${s.i('installment')}')),
                        DataCell(Text(Dates.day(s['due_date']))),
                        DataCell(Text(Money.format(s.i('total_due'), st.currency))),
                        DataCell(Text(Money.format(s.i('ending_balance'), st.currency))),
                      ]),
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
