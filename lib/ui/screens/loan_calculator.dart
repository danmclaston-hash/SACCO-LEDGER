import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/loan_math.dart';
import '../../core/money.dart';
import '../widgets.dart';
import '../text.dart';

/// Big, simple choices for how a loan works. Used in Group Settings, the calculator and for one loan.
class LoanRulesEditor extends StatefulWidget {
  final LoanTerms value;
  final ValueChanged<LoanTerms> onChanged;
  final String currency;
  final bool enabled;
  const LoanRulesEditor({super.key, required this.value, required this.onChanged, required this.currency, this.enabled = true});
  @override
  State<LoanRulesEditor> createState() => _LoanRulesEditorState();
}

class _LoanRulesEditorState extends State<LoanRulesEditor> {
  late final rate = TextEditingController(text: _num(widget.value.rate));
  late final lateAmount = TextEditingController(text: widget.value.lateAmount == 0 ? '' : Money.plain(widget.value.lateAmount, widget.currency));
  late final latePct = TextEditingController(text: widget.value.latePct == 0 ? '' : _num(widget.value.latePct));
  late final cap = TextEditingController(text: widget.value.capPct == null ? '' : _num(widget.value.capPct!));

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    rate.dispose();
    lateAmount.dispose();
    latePct.dispose();
    cap.dispose();
    super.dispose();
  }

  LoanTerms get t => widget.value;
  void set(LoanTerms n) => widget.onChanged(n);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final on = widget.enabled;
    Widget heading(String text, [String? term]) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(children: [
            Flexible(child: Text(text, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
            if (term != null) InfoTip(term),
          ]),
        );
    Widget stepper(String label, int value, int max, ValueChanged<int> onSet, {String? help}) => Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: tt.bodyMedium),
              if (help != null) Text(help, style: tt.labelSmall),
            ]),
          ),
          IconButton.outlined(onPressed: on && value > 0 ? () => onSet(value - 1) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          IconButton.outlined(onPressed: on && value < max ? () => onSet(value + 1) : null, icon: const Icon(Icons.add)),
        ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('1. How does interest work?'),
        _Choices(enabled: on, selected: t.interestMode, onSelect: (v) => set(t.copyWith(interestMode: v)), options: const [
          _Choice('none', Icons.money_off, 'No interest', 'Pay back exactly what you borrowed'),
          _Choice('once', Icons.looks_one_outlined, 'One-time', 'One % on the whole loan'),
          _Choice('monthly', Icons.calendar_view_month, 'Every month', 'A % added each month'),
          _Choice('yearly', Icons.calendar_today, 'Every year', 'A % a year, counted monthly'),
        ]),
        if (t.interestMode != 'none') ...[
          const SizedBox(height: 12),
          TextField(
            controller: rate,
            enabled: on,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: switch (t.interestMode) {
                'once' => 'Interest (% of the loan, once)',
                'monthly' => 'Interest (% each month)',
                _ => 'Interest (% a year)'
              },
              suffixText: '%',
              helperText: 'Like 10, or 2.5',
            ),
            onChanged: (v) {
              final r = double.tryParse(v.trim());
              if (r != null && r >= 0 && r <= 100) set(t.copyWith(rate: r));
            },
          ),
        ],
        if (t.timeBased) ...[
          heading('Counted on'),
          _Choices(enabled: on, selected: t.calculation, onSelect: (v) => set(t.copyWith(calculation: v)), options: const [
            _Choice('flat', Icons.horizontal_rule, 'The full loan', 'Same interest every month'),
            _Choice('reducing_balance', Icons.trending_down, 'What is still owed', 'Interest shrinks as you pay'),
          ]),
          const SizedBox(height: 12),
          stepper('Interest-free months', t.freeMonths, 59, (v) => set(t.copyWith(freeMonths: v)),
              help: 'Interest starts after these months. 0 = from the first month.'),
        ],
        heading('2. How is it paid back?'),
        _Choices(enabled: on, selected: t.plan, onSelect: (v) => set(t.copyWith(plan: v)), options: const [
          _Choice('monthly', Icons.event_repeat, 'A part every month', 'Smaller payments, each month'),
          _Choice('end', Icons.event_available, 'All at the end', 'One payment on the last day'),
        ]),
        heading('3. If a payment is late', 'arrears'),
        _Choices(enabled: on, selected: t.lateType, onSelect: (v) => set(t.copyWith(lateType: v)), options: const [
          _Choice('none', Icons.block, 'No late fee', 'Nothing is added'),
          _Choice('fixed', Icons.payments_outlined, 'Fixed amount', 'The same amount each time'),
          _Choice('percent', Icons.percent, '% of missed payment', 'Grows with the missed amount'),
        ]),
        if (t.lateType != 'none') ...[
          const SizedBox(height: 12),
          if (t.lateType == 'fixed')
            TextField(
              controller: lateAmount,
              enabled: on,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Late fee (${widget.currency})'),
              onChanged: (v) => set(t.copyWith(lateAmount: Money.parse(v, widget.currency) ?? 0)),
            )
          else
            TextField(
              controller: latePct,
              enabled: on,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Late fee (% of the missed payment)', suffixText: '%'),
              onChanged: (v) {
                final r = double.tryParse(v.trim());
                if (r != null && r >= 0 && r <= 100) set(t.copyWith(latePct: r));
              },
            ),
          const SizedBox(height: 12),
          Text('Added', style: tt.bodyMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (v, l) in const [('once', 'Once'), ('day', 'Every day'), ('week', 'Every week'), ('month', 'Every month')])
              ChoiceChip(label: Text(l), selected: t.lateEvery == v, onSelected: on ? (_) => set(t.copyWith(lateEvery: v)) : null),
          ]),
          const SizedBox(height: 12),
          stepper('Grace days', t.graceDays, 90, (v) => set(t.copyWith(graceDays: v)), help: 'Days after the due date before any fee.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: t.capPct != null,
            onChanged: on
                ? (v) {
                    if (v && cap.text.isEmpty) cap.text = '50';
                    set(v ? t.copyWith(capPct: double.tryParse(cap.text) ?? 50) : t.copyWith(clearCap: true));
                  }
                : null,
            title: const Text('Limit total late fees'),
            subtitle: const Text('Fair to the borrower: fees stop growing at this limit.'),
          ),
          if (t.capPct != null)
            TextField(
              controller: cap,
              enabled: on,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Most late fees can reach (% of the loan)', suffixText: '%'),
              onChanged: (v) {
                final r = double.tryParse(v.trim());
                if (r != null && r >= 0 && r <= 1000) set(t.copyWith(capPct: r));
              },
            ),
        ],
      ],
    );
  }
}

class _Choice {
  final String value;
  final IconData icon;
  final String title;
  final String subtitle;
  const _Choice(this.value, this.icon, this.title, this.subtitle);
}

/// Big tap targets in a grid: easy on a phone, readable for anyone.
class _Choices extends StatelessWidget {
  final List<_Choice> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool enabled;
  const _Choices({required this.options, required this.selected, required this.onSelect, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 520 ? options.length.clamp(1, 4) : 2;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options)
          SizedBox(
            width: w,
            child: Material(
              color: o.value == selected ? cs.primaryContainer : cs.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: o.value == selected ? cs.primary : cs.outlineVariant, width: o.value == selected ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: enabled ? () => onSelect(o.value) : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(o.icon, color: o.value == selected ? cs.primary : cs.onSurfaceVariant),
                      const Spacer(),
                      if (o.value == selected) Icon(Icons.check_circle, size: 18, color: cs.primary),
                    ]),
                    const SizedBox(height: 6),
                    Text(o.title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(o.subtitle, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

/// Short summary of what a loan will cost. Used in the calculator and when applying.
class LoanSummary extends StatelessWidget {
  final int principal;
  final int term;
  final LoanTerms terms;
  final String currency;
  final DateTime start;
  final bool showSchedule;
  const LoanSummary(
      {super.key, required this.principal, required this.term, required this.terms, required this.currency, required this.start, this.showSchedule = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    String m(int v) => Money.format(v, currency);
    final s = loanSchedule(principal, term, terms, start);
    if (s.isEmpty) return const EmptyNote('Enter an amount and the number of months.');
    final interest = s.fold<int>(0, (a, i) => a + i.interest);
    final firstInterest = s.firstWhere((i) => i.interest > 0, orElse: () => s.last);
    final interestStarts = !terms.hasInterest
        ? 'Never'
        : terms.plan == 'end'
            ? 'Paid with the loan on ${Dates.day(s.last.due)}'
            : terms.interestMode == 'once'
                ? 'Shared across every payment'
                : 'Month ${firstInterest.n} (${Dates.day(firstInterest.due)})';
    Widget row(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: tt.bodyMedium)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(b,
                  textAlign: TextAlign.end,
                  style: tt.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: bold ? cs.primary : null)),
            ),
          ]),
        );
    return SaccoCard(
      color: cs.primaryContainer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Pay back in total', style: tt.labelMedium),
        Text(m(principal + interest), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
        const SizedBox(height: 8),
        row('Borrowed', m(principal)),
        row('Interest', m(interest)),
        row('Interest starts', interestStarts),
        if (terms.plan == 'end')
          row('One payment on', Dates.day(s.last.due), bold: true)
        else ...[
          row('Each month',
              s.length > 1 && s.first.total != s[1].total ? 'From ${m(s.map((i) => i.total).reduce((a, b) => a < b ? a : b))}' : m(s.first.total)),
          row('Last payment on', Dates.day(s.last.due), bold: true),
        ],
        const SizedBox(height: 6),
        Text(describeInterest(terms), style: tt.bodySmall),
        Text(describeLateFee(terms, m), style: tt.bodySmall),
        if (showSchedule && s.length > 1) ...[
          const Divider(),
          for (final i in s)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${i.n}', style: tt.labelMedium)),
                Expanded(child: Text(Dates.day(i.due), style: tt.bodySmall)),
                Flexible(
                  flex: 2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(m(i.total), style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                    if (i.interest > 0) Text('incl. ${m(i.interest)} interest', textAlign: TextAlign.end, style: tt.labelSmall),
                  ]),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// "If I borrow this, what do I bring back, and what if I am late?"
class LoanCalculatorScreen extends StatefulWidget {
  const LoanCalculatorScreen({super.key});
  @override
  State<LoanCalculatorScreen> createState() => _LoanCalculatorScreenState();
}

class _LoanCalculatorScreenState extends State<LoanCalculatorScreen> {
  final amount = TextEditingController();
  final months = TextEditingController(text: '3');
  LoanTerms? terms;
  bool tryOther = false;
  double daysLate = 10;

  @override
  void dispose() {
    amount.dispose();
    months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final group = LoanTerms.fromGroup(st.org!);
    final t = tryOther ? (terms ?? group) : group;
    final p = Money.parse(amount.text, st.currency) ?? 0;
    final n = (int.tryParse(months.text.trim()) ?? 0).clamp(0, 60);
    final start = Dates.today();
    final s = loanSchedule(p, n, t, start);
    String m(int v) => Money.format(v, st.currency);
    final firstPay = s.isEmpty ? 0 : s.first.total;
    final fee = lateFeeFor(firstPay, daysLate.round(), t);
    final cap = lateFeeCap(p, t);
    final shownFee = cap != null && fee > cap ? cap : fee;

    return Scaffold(
      appBar: AppBar(title: const Text('Loan calculator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: MoneyField(controller: amount, label: 'Amount to borrow', currency: st.currency, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: months,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Months'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          gap,
          LoanSummary(principal: p, term: n, terms: t, currency: st.currency, start: start, showSchedule: true),
          gap,
          if (t.lateType != 'none' && s.isNotEmpty)
            SaccoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Flexible(child: Text('If the first payment is late', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                  const InfoTip('arrears'),
                ]),
                Text('${daysLate.round()} days late', style: tt.bodyMedium),
                Slider(value: daysLate, min: 0, max: 120, divisions: 120, label: '${daysLate.round()} days', onChanged: (v) => setState(() => daysLate = v)),
                Text(
                  shownFee == 0 ? 'No late fee yet.' : 'Late fee: ${m(shownFee)}${cap != null && fee > cap ? ' (limit reached)' : ''}',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: shownFee == 0 ? cs.primary : cs.error),
                ),
                Text('Then pay ${m(firstPay + shownFee)} instead of ${m(firstPay)} for that payment.', style: tt.bodySmall),
              ]),
            ),
          gap,
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: tryOther,
            onChanged: (v) => setState(() {
              tryOther = v;
              terms ??= group;
            }),
            title: const Text('Try other loan rules'),
            subtitle: Text(tryOther ? 'Only for this calculator. Your group\'s rules stay the same.' : 'Now using your group\'s rules.'),
          ),
          if (tryOther) LoanRulesEditor(value: terms ?? group, currency: st.currency, onChanged: (v) => setState(() => terms = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Group Settings: the group's own loan rules. Only the group admin can change them.
class LoanRulesCard extends StatefulWidget {
  const LoanRulesCard({super.key});
  @override
  State<LoanRulesCard> createState() => _LoanRulesCardState();
}

class _LoanRulesCardState extends State<LoanRulesCard> {
  LoanTerms? draft;
  String? loadedFor;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    if (loadedFor != st.orgId) {
      loadedFor = st.orgId;
      draft = LoanTerms.fromGroup(st.org!);
    }
    final t = draft!;
    final changed = t.toJson().toString() != LoanTerms.fromGroup(st.org!).toJson().toString();
    return SaccoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Flexible(child: Text('Loan rules', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          const InfoTip('loan_limit'),
        ]),
        Text('New loans use these. Loans already given keep the rules they started with.', style: tt.bodySmall),
        LoanRulesEditor(
          key: ValueKey(loadedFor),
          value: t,
          enabled: st.role.isOrgAdmin,
          currency: st.currency,
          onChanged: (v) => setState(() => draft = v),
        ),
        gap,
        Text('Example: 100,000 for 3 months', style: tt.labelLarge),
        const SizedBox(height: 6),
        LoanSummary(
          principal: Money.parse('100000', st.currency)!,
          term: 3,
          terms: t,
          currency: st.currency,
          start: Dates.today(),
        ),
        if (st.role.isOrgAdmin) ...[
          gap,
          FilledButton(
            onPressed: busy || !changed
                ? null
                : () async {
                    setState(() => busy = true);
                    final ok = await runAndTell(context, () => st.api.setLoanRules(st.orgId, t.toJson()), done: 'Loan rules saved. New loans will use them.');
                    if (!context.mounted) return;
                    setState(() {
                      busy = false;
                      if (ok) loadedFor = null;
                    });
                  },
            child: Text(changed ? 'Save loan rules' : 'Saved'),
          ),
        ],
      ]),
    );
  }
}
