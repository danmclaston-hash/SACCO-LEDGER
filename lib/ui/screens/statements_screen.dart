import 'package:flutter/material.dart' hide Text, InputDecoration;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/pages.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import '../text.dart';

/// Who paid what, for each cycle (circle). Members see their own; officers pick anyone.
class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key});
  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  int? cycle;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final memberId = st.statementMemberId ?? st.myMemberId ?? st.members.firstOrNull?.s('id');
    final cycles = st.org!.i('cycle_number');
    if (memberId == null) return const AppPageView(children: [EmptyNote('No members yet.')]);

    return AppPageView(
      children: [
        if (st.role.isOfficer)
          MemberPicker(
              key: ValueKey(memberId), label: 'Member', value: memberId, members: st.members, onChanged: (v) => st.goTo(AppPage.statements, memberId: v)),
        DropdownButtonFormField<int?>(
          initialValue: cycle,
          decoration: InputDecoration(labelText: 'Cycle'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('All cycles')),
            for (var c = cycles; c >= 1; c--) DropdownMenuItem<int?>(value: c, child: Text('Cycle $c')),
          ],
          onChanged: (v) => setState(() => cycle = v),
        ),
        Loaded<Json>(
          id: '$memberId-$cycle',
          load: () => st.api.statement(st.orgId, memberId, cycle: cycle),
          builder: (context, data) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final w in _statement(context, st, data)) Padding(padding: const EdgeInsets.only(bottom: 16), child: w),
          ]),
        ),
      ],
    );
  }

  List<Widget> _statement(BuildContext context, AppState st, Json data) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return [
      Row(
        children: [
          Expanded(
            child: BalanceStatCard(
              title: 'Savings',
              amount: money(context, data.i('savings')),
              subtitle: 'Shares and deposits',
              icon: Icons.savings,
              color: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BalanceStatCard(
              title: 'Loan Left',
              amount: money(context, data.i('loan_balance')),
              subtitle: 'Fines paid ${money(context, data.i('fines'))}',
              icon: Icons.request_quote,
              color: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _pdf(st, data),
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('Print / PDF'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _csv(data)));
              if (context.mounted) showMsg(context, 'Copied as CSV. Paste it in a spreadsheet.');
            },
            icon: const Icon(Icons.table_chart, size: 16),
            label: const Text('Copy CSV'),
          ),
        ],
      ),
      if (data.l('rows').isEmpty) const EmptyNote('No transactions in this period.'),
      for (final r in data.l('rows').reversed)
        SaccoCard(
          radius: 12,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.s('description'),
                      style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold, decoration: r.b('is_reversed') ? TextDecoration.lineThrough : null),
                    ),
                  ),
                  Text(
                    r.i('credit') > 0 ? '+${money(context, r.i('credit'))}' : '-${money(context, r.i('debit'))}',
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                  ),
                ],
              ),
              Text(
                '${Dates.dayTime(r['date'])} • #${r.i('journal_number')} • Cycle ${r.i('cycle_number')} • ${r.s('account_name')}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              Text(
                'Recorded by ${r.s('recorded_by')}${r.n('channel') != null ? ' • ${Channel.labelOf(r.s('channel'))}' : ''}${r.n('external_ref') != null ? ' • ID ${r.s('external_ref')}' : ''}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      for (final p in data.l('payouts'))
        SaccoCard(
          radius: 12,
          padding: const EdgeInsets.all(12),
          color: cs.secondaryContainer,
          child: Text('Cycle ${p.i('cycle_number')} share-out: ${money(context, p.i('payout'))} (saved ${money(context, p.i('savings'))})'),
        ),
    ];
  }

  String _csv(Json s) {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('Date,Journal,Cycle,Description,Account,Debit,Credit,Channel,Transaction ID,Recorded by,Reversed\n');
    for (final r in s.l('rows')) {
      b.writeln(
        [
          q(Dates.dayTime(r['date'])),
          r.i('journal_number'),
          r.i('cycle_number'),
          q(r.s('description')),
          q(r.s('account_name')),
          r.i('debit'),
          r.i('credit'),
          q(r.s('channel')),
          q(r.s('external_ref')),
          q(r.s('recorded_by')),
          r.b('is_reversed') ? 'yes' : 'no',
        ].join(','),
      );
    }
    return b.toString();
  }

  Future<void> _pdf(AppState st, Json s) async {
    final m = s.m('member');
    String f(int v) => Money.format(v, st.currency);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(st.org!.s('name'), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Member statement: ${m.s('full_name')} (M${m.i('member_no')})'),
          pw.Text('Printed ${Dates.dayTime(DateTime.now())}${cycle != null ? ' - Cycle $cycle' : ''}'),
          pw.SizedBox(height: 8),
          pw.Text('Savings ${f(s.i('savings'))}   Loan left ${f(s.i('loan_balance'))}   Emergency ${f(s.i('emergency'))}   Fines ${f(s.i('fines'))}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Date', '#', 'Description', 'Paid in', 'Out', 'ID'],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            data: [
              for (final r in s.l('rows'))
                [
                  Dates.day(r['date']),
                  '${r.i('journal_number')}',
                  '${r.s('description')}${r.b('is_reversed') ? ' (REVERSED)' : ''}',
                  r.i('credit') > 0 ? f(r.i('credit')) : '',
                  r.i('debit') > 0 ? f(r.i('debit')) : '',
                  r.s('external_ref'),
                ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('SACCO Ledger keeps records only. It does not hold or move money.', style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
    await Printing.layoutPdf(name: 'statement-${m.s('full_name')}.pdf', onLayout: (_) => doc.save());
  }
}
