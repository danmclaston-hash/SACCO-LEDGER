import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'statements_screen.dart';

/// Officers: journals, trial balance, audit trail. Members: their own statement.
class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    if (!st.isOfficer) return const StatementsScreen();
    return DefaultTabController(
      key: ValueKey(st.ledgerTab),
      length: 3,
      initialIndex: st.ledgerTab,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Journals'), Tab(text: 'Trial Balance'), Tab(text: 'Audit Trail')]),
        Expanded(child: TabBarView(children: [_Journals(), _TrialBalance(), _Audit()])),
      ]),
    );
  }
}

class _Journals extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AppPageView(children: [
      if (st.journals.isEmpty) const EmptyNote('No journal postings found.'),
      for (final j in st.journals)
        SaccoCard(
          radius: 12,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('#${j.i('journal_number')} • ${j.s('type').toUpperCase()} • Cycle ${j.i('cycle_number')}',
                      style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary))),
              if (j.b('is_reversed')) Pill(text: 'REVERSED', color: cs.error, foreground: cs.onError),
              if (st.canReview && !j.b('is_reversed') && j.s('type') != 'reversal' && j.s('type') != 'share_out')
                TextButton(onPressed: () => _reverse(context, st, j), child: Text('Reverse', style: TextStyle(color: cs.error))),
            ]),
            Text(j.s('description'), style: tt.bodySmall),
            Text(
                'By ${j.s('actor_name')} • ${Dates.dayTime(j['created_at'])}${j.n('external_ref') != null ? ' • ID ${j.s('external_ref')}' : ''}${j.n('channel') != null ? ' • ${channelNames[j.s('channel')]}' : ''}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const Divider(height: 12),
            for (final line in j.l('lines'))
              Row(children: [
                Expanded(
                    child: Text('${line.s('account_code')} - ${line.s('account_name')}${line.n('member_name') != null ? ' (${line.s('member_name')})' : ''}',
                        style: tt.labelSmall)),
                Text(line.i('debit') > 0 ? 'Dr ${money(context, line.i('debit'))}' : 'Cr ${money(context, line.i('credit'))}',
                    style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              ]),
          ]),
        ),
    ]);
  }

  void _reverse(BuildContext context, AppState st, Json j) {
    final reason = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Confirm Journal Reversal',
        confirm: 'Execute Reversal',
        fields: (ctx, set) => [
          Text('#${j.i('journal_number')} ${j.s('description')}\nNothing is deleted. An opposite entry is added, with your name and reason.'),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason for Reversal')),
        ],
        onConfirm: (ctx) => runAndClose(ctx, st, () => st.api.reverseJournal(j.s('id'), reason.text), done: 'Reversed.'),
      ),
    );
  }
}

class _TrialBalance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return FutureBuilder<Json>(
      key: ValueKey(st.journals.length),
      future: st.api.trialBalance(st.orgId),
      builder: (context, snap) {
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text(snap.error.toString()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final t = snap.data!;
        final tt = Theme.of(context).textTheme;
        final ok = t.b('balanced');
        return AppPageView(children: [
          SaccoCard(
            color: ok ? okGreenBg : Theme.of(context).colorScheme.errorContainer,
            child: Row(children: [
              Icon(ok ? Icons.verified : Icons.error, color: ok ? okGreen : Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Total Debits: ${money(context, t.i('total_debit'))} • Total Credits: ${money(context, t.i('total_credit'))}${ok ? ' • BALANCED' : ' • NOT BALANCED'}',
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: ok ? okGreen : null)),
              ),
            ]),
          ),
          for (final r in t.l('rows'))
            SaccoCard(
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Text('${r.s('code')} • ${r.s('name')}', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Dr ${money(context, r.i('debit'))}', style: tt.labelSmall),
                  Text('Cr ${money(context, r.i('credit'))}', style: tt.labelSmall),
                  Text('Net ${money(context, r.i('net'))}', style: tt.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ]),
            ),
        ]);
      },
    );
  }
}

class _Audit extends StatefulWidget {
  @override
  State<_Audit> createState() => _AuditState();
}

class _AuditState extends State<_Audit> {
  Json? check;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Json>>(
      key: ValueKey(st.journals.length),
      future: st.api.audit(st.orgId),
      builder: (context, snap) {
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text(snap.error.toString()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return AppPageView(children: [
          SaccoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Immutable Governance Audit Trail', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text('Each row seals the one before it. If anyone changes an old row, this check fails.', style: tt.bodySmall),
              gap,
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final r = await st.api.verifyAudit(st.orgId);
                          if (mounted) setState(() => check = r);
                        } catch (e) {
                          if (context.mounted) showMsg(context, e.toString(), error: true);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                icon: const Icon(Icons.verified_user),
                label: const Text('Check for tampering'),
              ),
              if (check != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: check!.b('ok')
                      ? Text('Passed. ${check!.i('checked')} rows are intact.', style: const TextStyle(color: okGreen, fontWeight: FontWeight.bold))
                      : Text('FAILED at row ${check!.i('broken_at_seq')}. Records may have been changed. Tell your auditor.',
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          if (snap.data!.isEmpty) const EmptyNote('No audit records found.'),
          for (final a in snap.data!)
            SaccoCard(
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a.i('seq')}. ${a.s('action')}', style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
                Text(a.s('details'), style: tt.bodySmall),
                Text('${a.s('actor_name')} • ${Dates.dayTime(a['created_at'])}', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
        ]);
      },
    );
  }
}
