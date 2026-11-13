import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'statements_screen.dart';
import '../text.dart';

/// Officers: journals, trial balance, audit trail. Members: their own statement.
class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    if (!st.role.isOfficer) return const StatementsScreen();
    return DefaultTabController(
      key: ValueKey(st.ledgerTab),
      length: 3,
      initialIndex: st.ledgerTab,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: tr('Journals')),
              Tab(text: tr('Trial Balance')),
              Tab(text: tr('Audit Trail')),
            ],
          ),
          Expanded(child: TabBarView(children: [_Journals(), _TrialBalance(), _Audit()])),
        ],
      ),
    );
  }
}

class _Journals extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return AppPageView(
      children: [
        if (st.journals.isEmpty) const EmptyNote('No journal postings found.'),
        for (final j in st.journals) _JournalTile(j, onReverse: () => _reverse(context, st, j)),
      ],
    );
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
          TextField(
            controller: reason,
            decoration: InputDecoration(labelText: 'Reason for Reversal'),
          ),
        ],
        onConfirm: (ctx) => runAndClose(ctx, () => st.api.reverseJournal(j.s('id'), reason.text), done: 'Reversed.'),
      ),
    );
  }
}

class _TrialBalance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return Loaded<Json>(
      load: () => st.api.trialBalance(st.orgId),
      builder: (context, t) {
        final tt = Theme.of(context).textTheme;
        final ok = t.b('balanced');
        return AppPageView(
          children: [
            SaccoCard(
              color: ok ? okGreenBg : Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(ok ? Icons.verified : Icons.error, color: ok ? okGreen : Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total Debits: ${money(context, t.i('total_debit'))} • Total Credits: ${money(context, t.i('total_credit'))}${ok ? ' • BALANCED' : ' • NOT BALANCED'}',
                      style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: ok ? okGreen : null),
                    ),
                  ),
                ],
              ),
            ),
            for (final r in t.l('rows'))
              SaccoCard(
                radius: 12,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${r.s('code')} • ${r.s('name')}', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Dr ${money(context, r.i('debit'))}', style: tt.labelSmall),
                        Text('Cr ${money(context, r.i('credit'))}', style: tt.labelSmall),
                        Text('Net ${money(context, r.i('net'))}', style: tt.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
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
    return Loaded<List<Json>>(
      load: () => st.api.audit(st.orgId),
      builder: (context, rows) {
        return AppPageView(
          children: [
            SaccoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Flexible(child: Text('Immutable Governance Audit Trail', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                    const InfoTip('audit_trail'),
                  ]),
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
                          ? Text(
                              'Passed. ${check!.i('checked')} rows are intact.',
                              style: const TextStyle(color: okGreen, fontWeight: FontWeight.bold),
                            )
                          : Text(
                              'FAILED at row ${check!.i('broken_at_seq')}. Records may have been changed. Tell your auditor.',
                              style: TextStyle(color: cs.error, fontWeight: FontWeight.bold),
                            ),
                    ),
                ],
              ),
            ),
            if (rows.isEmpty) const EmptyNote('No audit records found.'),
            for (final a in rows)
              SaccoCard(
                radius: 12,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a.i('seq')}. ${a.s('action')}',
                      style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                    ),
                    Text(a.s('details'), style: tt.bodySmall),
                    Text('${a.s('actor_name')} • ${Dates.dayTime(a['created_at'])}', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One record in plain words: what happened, how much, when and by whom.
/// Tap to see the account lines (debit and credit) and, for the treasurer, Reverse.
class _JournalTile extends StatelessWidget {
  final Json j;
  final VoidCallback onReverse;
  const _JournalTile(this.j, {required this.onReverse});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final reversed = j.b('is_reversed');
    final canReverse = st.role.handlesMoney && !reversed && j.s('type') != 'reversal' && j.s('type') != 'share_out';
    return SaccoCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          title: Text(j.s('description'), maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '#${j.i('journal_number')} • ${Dates.dayTime(j['created_at'])}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(context, j.i('total')),
                style: look.numbers(tt.titleSmall).copyWith(fontWeight: FontWeight.w700, decoration: reversed ? TextDecoration.lineThrough : null)),
            if (reversed) Text('Reversed', style: tt.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.w700)),
          ]),
          children: [
            Align(alignment: Alignment.centerLeft, child: Text('Recorded by ${j.s('actor_name')} • Cycle ${j.i('cycle_number')}', style: tt.bodySmall)),
            if (j.n('external_ref') != null || j.n('channel') != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  [if (j.n('channel') != null) Channel.labelOf(j.s('channel')), if (j.n('external_ref') != null) 'ID ${j.s('external_ref')}'].join(' • '),
                  style: tt.bodySmall,
                ),
              ),
            const SizedBox(height: 6),
            for (final line in j.l('lines'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${line.s('account_name')}${line.n('member_name') != null ? ' (${line.s('member_name')})' : ''}',
                      style: tt.bodySmall,
                    ),
                  ),
                  Text(
                    line.i('debit') > 0 ? 'Debit ${money(context, line.i('debit'))}' : 'Credit ${money(context, line.i('credit'))}',
                    style: look.numbers(tt.bodySmall).copyWith(fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            if (canReverse)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onReverse,
                  icon: Icon(Icons.undo_rounded, color: cs.error, size: 18),
                  label: Text('Reverse this record', style: TextStyle(color: cs.error)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
