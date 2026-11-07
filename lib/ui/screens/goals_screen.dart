import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/goal_math.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../charts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'channels_screen.dart';

/// Savings goals: plan a target, see what each person brings, track progress.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final active = st.goals.where((g) => g.s('status') == 'active').toList();
    final closed = st.goals.where((g) => g.s('status') != 'active').toList();
    return AppPageView(children: [
      if (st.allocation.i('total') > 0) AllocationBar(allocation: st.allocation, currency: st.currency),
      const GoalCalculator(),
      SectionTitle('Group goals (${active.length})',
          trailing: st.role.canRunMeetings
              ? FilledButton.icon(onPressed: () => showCreateGoal(context), icon: const Icon(Icons.flag, size: 16), label: const Text('New goal'))
              : null),
      if (active.isEmpty)
        EmptyNote(st.role.canRunMeetings ? 'No goals yet. Use the calculator above, then save it as a goal.' : 'No goals yet. Your officers can set one.'),
      for (final g in active) GoalCard(g),
      if (closed.isNotEmpty) ...[
        const SectionTitle('Finished goals'),
        for (final g in closed) GoalCard(g),
      ],
    ]);
  }
}


enum _Mode { byDeadline, byAmount }

/// Works for everyone, even before a goal exists. Nothing is saved until an officer taps "Save as goal".
class GoalCalculator extends StatefulWidget {
  const GoalCalculator({super.key});
  @override
  State<GoalCalculator> createState() => _GoalCalculatorState();
}

class _GoalCalculatorState extends State<GoalCalculator> {
  _Mode mode = _Mode.byDeadline;
  Frequency freq = Frequency.weekly;
  final target = TextEditingController();
  final people = TextEditingController();
  final periods = TextEditingController(text: '4');
  final each = TextEditingController();
  bool peopleSet = false;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (!peopleSet && st.activeMembers.isNotEmpty) {
      people.text = '${st.activeMembers.length}';
      peopleSet = true;
    }
    final t = Money.parse(target.text, st.currency) ?? 0;
    final n = int.tryParse(people.text.trim()) ?? 0;
    final p = int.tryParse(periods.text.trim()) ?? 0;
    final e = Money.parse(each.text, st.currency) ?? 0;
    final today = DateTime.now();
    String m(int v) => Money.format(v, st.currency);

    Widget? result;
    Map<String, Object?>? plan;
    if (mode == _Mode.byDeadline && t > 0 && n > 0 && p > 0) {
      final exact = GoalMath.exactPerPerson(t, n, p);
      final carry = GoalMath.perPerson(t, n, p);
      final finish = GoalMath.finishDate(today, p, freq);
      result = _Answer(
        big: 'Each person brings ${m(carry)} every ${freq.one}',
        lines: [
          'Exact share: ${m(exact)}. Rounded up so it is easy to carry.',
          'All $n together: ${m(carry * n)} a ${freq.one}. After $p ${p == 1 ? freq.one : freq.many}: ${m(GoalMath.reach(n, carry, p))}.',
          'Ready by ${Dates.day(finish)}.',
        ],
      );
      plan = {'target': t, 'end': finish, 'perPerson': carry};
    } else if (mode == _Mode.byAmount && t > 0 && n > 0 && e > 0) {
      final need = GoalMath.periodsNeeded(t, n, e);
      final finish = GoalMath.finishDate(today, need, freq);
      final inP = p > 0 ? GoalMath.reach(n, e, p) : null;
      result = _Answer(
        big: 'Done in $need ${need == 1 ? freq.one : freq.many}',
        lines: [
          'All $n bring ${m(e)} each: ${m(e * n)} a ${freq.one}.',
          'Ready by ${Dates.day(finish)}.',
          if (inP != null) 'In $p ${p == 1 ? freq.one : freq.many} you would have ${m(inP)} (${(inP * 100 / t).clamp(0, 999).round()}% of the goal).',
        ],
      );
      plan = {'target': t, 'end': finish, 'perPerson': e};
    }

    void rebuild(_) => setState(() {});
    return SaccoCard(
      elevation: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExcludeSemantics(child: Icon(Icons.calculate_outlined, color: cs.primary)),
          const SizedBox(width: 8),
          Expanded(child: Text('Plan a goal', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        ]),
        Text('Try numbers. Nothing is saved until you choose to.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        gap,
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.byDeadline, label: Text('By when?'), icon: Icon(Icons.event)),
            ButtonSegment(value: _Mode.byAmount, label: Text('How much each?'), icon: Icon(Icons.payments_outlined)),
          ],
          selected: {mode},
          onSelectionChanged: (s) => setState(() => mode = s.first),
        ),
        gap,
        Row(children: [
          Expanded(flex: 3, child: MoneyField(controller: target, label: 'Goal', currency: st.currency, onChanged: rebuild)),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: TextField(
                  controller: people, keyboardType: TextInputType.number, onChanged: rebuild, decoration: const InputDecoration(labelText: 'People'))),
        ]),
        gap,
        Wrap(spacing: 8, children: [
          for (final f in Frequency.values) ChoiceChip(label: Text('Every ${f.one}'), selected: freq == f, onSelected: (_) => setState(() => freq = f)),
        ]),
        gap,
        if (mode == _Mode.byAmount) ...[
          MoneyField(controller: each, label: 'Each person brings, every ${freq.one}', currency: st.currency, onChanged: rebuild),
          gap,
        ],
        TextField(
          controller: periods,
          keyboardType: TextInputType.number,
          onChanged: rebuild,
          decoration:
              InputDecoration(labelText: mode == _Mode.byDeadline ? 'How many ${freq.many}?' : 'Optional: what if we only have this many ${freq.many}?'),
        ),
        gap,
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
          child: result ?? Text('Fill in the goal and the boxes above to see the answer.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        if (plan != null && st.role.canRunMeetings) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                showCreateGoal(context, target: plan!['target'] as int, end: plan['end'] as DateTime, frequency: freq, perPerson: plan['perPerson'] as int),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Save as group goal'),
          ),
        ],
      ]),
    );
  }
}

class _Answer extends StatelessWidget {
  final String big;
  final List<String> lines;
  const _Answer({required this.big, required this.lines});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Semantics(
        liveRegion: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(big, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
          const SizedBox(height: 4),
          for (final l in lines) Text(l, style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer)),
        ]),
      ),
    );
  }
}


class GoalCard extends StatelessWidget {
  final Json g;
  const GoalCard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = statusOf(g);
    final closed = g.s('status') != 'active';
    String m(int v) => Money.format(v, st.currency);
    final freq = Frequency.parse(g.s('frequency'));
    final (String label, Color color, Color fg) = closed
        ? ('CLOSED', Colors.grey, Colors.white)
        : s.done
            ? ('REACHED', okGreen, Colors.white)
            : s.onTrack
                ? ('ON TRACK', okGreenBg, okGreen)
                : ('BEHIND', warnOrange, Colors.white);
    return SaccoCard(
      radius: 12,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showGoalDetails(context, g),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(g.s('name'), style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
            Pill(text: label, color: color, foreground: fg),
          ]),
          const SizedBox(height: 10),
          Semantics(
            label: '${(s.percent * 100).round()} percent collected',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child:
                  LinearProgressIndicator(value: s.percent, minHeight: 12, color: ChartColors.series(context)[0], backgroundColor: cs.surfaceContainerHighest),
            ),
          ),
          const SizedBox(height: 8),
          Text('${m(s.collected)} of ${m(s.target)} • ${(s.percent * 100).round()}%', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (g.n('end_date') != null)
            Text(
                'Ends ${Dates.day(g['end_date'])}${!closed && s.periodsLeft > 0 ? ' • ${s.periodsLeft} ${s.periodsLeft == 1 ? freq.one : freq.many} left' : ''}',
                style: tt.bodySmall),
          if (g.i('per_person') > 0)
            Text('Plan: each brings ${m(g.i('per_person'))} every ${freq.one}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (!closed && !s.done && !s.onTrack && s.behindBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Behind by ${m(s.behindBy!)}.${s.catchUpEach != null ? ' To finish on time each brings ${m(s.catchUpEach!)} every ${freq.one}.' : ''}',
                style: tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
              ),
            ),
          if (g.i('pending') > 0) Text('${m(g.i('pending'))} more waits for checking.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (!st.role.isOfficer) Text('My part: ${m(g.i('mine'))}', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

GoalStatus statusOf(Json g) => GoalStatus.of(
      target: g.i('target'),
      collected: g.i('collected'),
      people: g.i('people'),
      start: DateTime.parse(g.s('start_date')),
      end: g.n('end_date') == null ? null : DateTime.parse(g.s('end_date')),
      frequency: Frequency.parse(g.s('frequency')),
      today: DateTime.now(),
    );

void showGoalDetails(BuildContext context, Json g) {
  final st = StateScope.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => StateScope(
      state: st,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text(g.s('name'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text('Counted from ${g.i('records')} checked record(s).', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          GoalChart(goal: g, currency: st.currency),
          const SizedBox(height: 12),
          if (g['by_member'] is List) ...[
            const SectionTitle('Who has brought what'),
            const SizedBox(height: 6),
            for (final m in g.l('by_member')) _MemberLine(name: m.s('name'), amount: m.i('amount'), plan: _memberPlan(g)),
          ],
          const SizedBox(height: 12),
          if (g.s('status') == 'active' && st.myMemberId != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheetCtx);
                showPaymentDialog(context, purpose: Purpose.savings, goalId: g.s('id'));
              },
              icon: const Icon(Icons.add),
              label: const Text('Pay toward this goal'),
            ),
          if (g.s('status') == 'active' && st.role.canRunMeetings) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: const Text('Close this goal?'),
                    content: const Text('No new money can be labelled for it. Money already collected stays in savings.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Close goal')),
                    ],
                  ),
                );
                if (ok != true) return;
                final err = await st.act(() => st.api.closeGoal(g.s('id')));
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                if (context.mounted) showMsg(context, err ?? 'Goal closed.', error: err != null);
              },
              child: const Text('Close goal'),
            ),
          ],
        ]),
      ),
    ),
  );
}

/// What each person should have brought by today, if the goal has an end date.
int? _memberPlan(Json g) {
  if (g.n('end_date') == null || g.i('people') == 0) return null;
  final planned = GoalMath.plannedBy(g.i('target'), DateTime.parse(g.s('start_date')), DateTime.parse(g.s('end_date')), DateTime.now());
  return (planned + g.i('people') - 1) ~/ g.i('people');
}

class _MemberLine extends StatelessWidget {
  final String name;
  final int amount;
  final int? plan;
  const _MemberLine({required this.name, required this.amount, this.plan});
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final short = plan != null && amount < plan!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(name, style: tt.bodyMedium)),
        Text(Money.format(amount, st.currency), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: plan == null
              ? const SizedBox.shrink()
              : Text(short ? '${Money.format(plan! - amount, st.currency)} short' : 'On track',
                  textAlign: TextAlign.right, style: tt.labelSmall?.copyWith(color: short ? cs.error : okGreen, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}


void showCreateGoal(BuildContext context, {int? target, DateTime? end, Frequency frequency = Frequency.weekly, int? perPerson}) {
  final st = StateScope.of(context);
  final name = TextEditingController();
  final amount = TextEditingController(text: target?.toString() ?? '');
  final each = TextEditingController(text: perPerson?.toString() ?? '');
  var freq = frequency;
  DateTime? endDate = end;
  showDialog(
    context: context,
    builder: (_) => StateScope(
      state: st,
      child: FormDialog(
        title: 'New group goal',
        confirm: 'Save goal',
        fields: (ctx, set) => [
          TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name, e.g. School fees')),
          MoneyField(controller: amount, label: 'Goal amount', currency: st.currency),
          Wrap(spacing: 8, children: [
            for (final f in Frequency.values) ChoiceChip(label: Text('Every ${f.one}'), selected: freq == f, onSelected: (_) => set(() => freq = f)),
          ]),
          MoneyField(controller: each, label: 'Each person brings (optional)', currency: st.currency),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  initialDate: endDate ?? DateTime.now().add(const Duration(days: 30)));
              if (d != null) set(() => endDate = d);
            },
            icon: const Icon(Icons.event),
            label: Text(endDate == null ? 'Pick an end date (optional)' : 'Ends ${Dates.day(endDate)}'),
          ),
          const Text('Money stays in the one savings account. When members pay, they can label it for this goal.', style: TextStyle(fontSize: 12)),
        ],
        onConfirm: (ctx) async {
          final t = Money.parse(amount.text, st.currency);
          if (name.text.trim().length < 2 || t == null) {
            showMsg(ctx, 'Write a name and the goal amount.', error: true);
            return;
          }
          await runAndClose(
            ctx,
            st,
            () => st.api.createGoal(st.orgId,
                name: name.text.trim(), target: t, start: DateTime.now(), end: endDate, frequency: freq.name, perPerson: Money.parse(each.text, st.currency)),
            done: 'Goal saved.',
          );
        },
      ),
    ),
  );
}
