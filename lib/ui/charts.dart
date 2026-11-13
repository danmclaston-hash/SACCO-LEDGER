import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../core/json.dart';
import '../core/money.dart';
import 'widgets.dart';
import 'text.dart';

/// Chart colours. Brand teal and gold first, then four more, in a fixed order.
/// Checked for colour-blind readers in light and dark. Never cycle: past 6 goals, fold into "Other goals".
class ChartColors {
  static const _light = [Color(0xFF00897B), Color(0xFFE5A00D), Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF6250D6), Color(0xFFE87BA4)];
  static const _dark = [Color(0xFF26A69A), Color(0xFFC98500), Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF9085E9), Color(0xFFD55181)];

  static List<Color> series(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;

  /// For "not for any goal" and the planned line: a quiet grey, not a series colour.
  static Color neutral(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF6B7774) : const Color(0xFFB7BFBC);
  static Color grid(BuildContext c) => Theme.of(c).colorScheme.outlineVariant.withValues(alpha: 0.6);
  static Color ink(BuildContext c) => Theme.of(c).colorScheme.onSurfaceVariant;
}

/// 1,250,000 -> 1.25M, 350,000 -> 350k. For axis labels only; tooltips show the full amount.
String compactMoney(int v) {
  final a = v.abs();
  String trim(double x) => x.toStringAsFixed(x >= 10 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '');
  if (a >= 1000000) return '${v < 0 ? '-' : ''}${trim(a / 1000000)}M';
  if (a >= 1000) return '${v < 0 ? '-' : ''}${trim(a / 1000)}k';
  return '$v';
}

/// "2026-11" -> "Nov".
String _monthLabel(String ym) => Dates.monthShort(int.tryParse(ym.split('-').last) ?? 1);

double _niceMax(int v) {
  if (v <= 0) return 1;
  final p = pow(10, (log(v) / ln10).floor()).toDouble();
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (v <= m * p) return m * p;
  }
  return v.toDouble();
}

class _Legend extends StatelessWidget {
  final List<(Color, String, String?)> items;
  const _Legend(this.items);
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Wrap(spacing: 16, runSpacing: 6, children: [
      for (final (color, label, value) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: tt.bodySmall),
          if (value != null) ...[const SizedBox(width: 4), Text(value, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold))],
        ]),
    ]);
  }
}

/// Every chart card can show its numbers as a plain list, for people who prefer reading to looking.
class _NumbersToggle extends StatefulWidget {
  final List<List<String>> rows; // first row is the header
  const _NumbersToggle(this.rows);
  @override
  State<_NumbersToggle> createState() => _NumbersToggleState();
}

class _NumbersToggleState extends State<_NumbersToggle> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton.icon(
        onPressed: () => setState(() => open = !open),
        icon: Icon(open ? Icons.expand_less : Icons.table_rows_outlined, size: 18),
        label: Text(open ? 'Hide numbers' : 'See the numbers'),
      ),
      if (open)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columnSpacing: 20,
            columns: [for (final h in widget.rows.first) DataColumn(label: Text(h, style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold)))],
            rows: [
              for (final r in widget.rows.skip(1)) DataRow(cells: [for (final c in r) DataCell(Text(c, style: tt.bodySmall))]),
            ],
          ),
        ),
    ]);
  }
}

class ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget chart;
  final Widget? legend;
  final List<List<String>>? numbers;
  const ChartCard({super.key, required this.title, required this.subtitle, required this.chart, this.legend, this.numbers});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SaccoCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(subtitle, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        if (legend != null) ...[const SizedBox(height: 10), legend!],
        const SizedBox(height: 12),
        SizedBox(height: 190, child: chart),
        if (numbers != null) _NumbersToggle(numbers!),
      ]),
    );
  }
}

FlTitlesData _titles(BuildContext context, {required Widget Function(double, TitleMeta) bottom, double? bottomInterval, required double interval}) {
  final st = Theme.of(context).textTheme.labelSmall?.copyWith(color: ChartColors.ink(context));
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 48,
        interval: interval,
        getTitlesWidget: (v, meta) => v == meta.max && v != 0 && meta.max % interval != 0
            ? const SizedBox.shrink()
            : SideTitleWidget(meta: meta, child: Text(compactMoney(v.round()), maxLines: 1, softWrap: false, style: st)),
      ),
    ),
    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: bottomInterval ?? 1, getTitlesWidget: bottom)),
  );
}

FlGridData _grid(BuildContext c, double interval) =>
    FlGridData(drawVerticalLine: false, horizontalInterval: interval, getDrawingHorizontalLine: (_) => FlLine(color: ChartColors.grid(c), strokeWidth: 1));

/// Money in and money out per month: two bars side by side. Only checked records.
class MoneyFlowChart extends StatelessWidget {
  final List<Json> flows;
  final String currency;
  final bool mine;
  const MoneyFlowChart({super.key, required this.flows, required this.currency, this.mine = false});

  @override
  Widget build(BuildContext context) {
    final colors = ChartColors.series(context);
    final inC = colors[0], outC = colors[1];
    final maxV = flows.fold<int>(0, (m, f) => max(m, max(f.i('paid_in'), f.i('paid_out'))));
    final top = _niceMax(maxV);
    final totalIn = flows.fold<int>(0, (a, f) => a + f.i('paid_in'));
    final totalOut = flows.fold<int>(0, (a, f) => a + f.i('paid_out'));
    final surface = Theme.of(context).colorScheme.surface;
    return ChartCard(
      title: mine ? 'My money, month by month' : 'Money in and out, month by month',
      subtitle: 'Last 12 months. Only checked records.',
      legend: _Legend([(inC, 'Paid in', Money.format(totalIn, currency)), (outC, 'Paid out', Money.format(totalOut, currency))]),
      numbers: [
        ['Month', 'Paid in', 'Paid out'],
        for (final f in flows) [f.s('month'), Money.format(f.i('paid_in'), currency), Money.format(f.i('paid_out'), currency)],
      ],
      chart: Semantics(
        label: 'Bar chart. In the last 12 months ${Money.format(totalIn, currency)} paid in and ${Money.format(totalOut, currency)} paid out.',
        child: BarChart(BarChartData(
          maxY: top,
          minY: 0,
          gridData: _grid(context, top / 4),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, interval: top / 4, bottom: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= flows.length || (flows.length > 6 && i.isOdd)) return const SizedBox.shrink();
            return SideTitleWidget(
                meta: meta,
                child: Text(_monthLabel(flows[i].s('month')), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ChartColors.ink(context))));
          }),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${_monthLabel(flows[gi].s('month'))} ${ri == 0 ? 'in' : 'out'}\n${Money.format(rod.toY.round(), currency)}',
                TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < flows.length; i++)
              BarChartGroupData(x: i, barsSpace: 2, groupVertically: false, barRods: [
                BarChartRodData(
                    toY: flows[i].i('paid_in').toDouble(),
                    color: inC,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    borderSide: BorderSide(color: surface, width: 0)),
                BarChartRodData(
                    toY: flows[i].i('paid_out').toDouble(), color: outC, width: 7, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              ]),
          ],
        )),
      ),
    );
  }
}

/// Total savings at the end of each month: one rising line.
class SavingsGrowthChart extends StatelessWidget {
  final List<Json> flows;
  final String currency;
  final bool mine;
  const SavingsGrowthChart({super.key, required this.flows, required this.currency, this.mine = false});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.series(context)[0];
    final maxV = flows.fold<int>(0, (m, f) => max(m, f.i('savings')));
    final top = _niceMax(maxV);
    final now = flows.isEmpty ? 0 : flows.last.i('savings');
    final first = flows.isEmpty ? 0 : flows.first.i('savings');
    return ChartCard(
      title: mine ? 'My savings over time' : 'Group savings over time',
      subtitle:
          'Savings at the end of each month. Now ${Money.format(now, currency)}${now > first ? ', up ${Money.format(now - first, currency)} in a year' : ''}.',
      numbers: [
        ['Month', 'Savings'],
        for (final f in flows) [f.s('month'), Money.format(f.i('savings'), currency)],
      ],
      chart: Semantics(
        label: 'Line chart of savings. Now ${Money.format(now, currency)}.',
        child: LineChart(LineChartData(
          minY: 0,
          maxY: top,
          minX: 0,
          maxX: max(1, flows.length - 1).toDouble(),
          gridData: _grid(context, top / 4),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, interval: top / 4, bottom: (v, meta) {
            final i = v.round();
            if (v != i || i < 0 || i >= flows.length || (flows.length > 6 && i.isOdd)) return const SizedBox.shrink();
            return SideTitleWidget(
                meta: meta,
                child: Text(_monthLabel(flows[i].s('month')), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ChartColors.ink(context))));
          }),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('${_monthLabel(flows[s.x.round()].s('month'))}\n${Money.format(s.y.round(), currency)}',
                      TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 12)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < flows.length; i++) FlSpot(i.toDouble(), flows[i].i('savings').toDouble())],
              color: c,
              barWidth: 2,
              isCurved: false,
              dotData: FlDotData(
                checkToShowDot: (s, d) => s.x == d.spots.last.x,
                getDotPainter: (s, p, d, i) => FlDotCirclePainter(radius: 4, color: c, strokeWidth: 2, strokeColor: Theme.of(context).colorScheme.surface),
              ),
              belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.10)),
            ),
          ],
        )),
      ),
    );
  }
}

/// A goal: the planned straight path (grey, dashed) against what really came in (teal).
class GoalChart extends StatelessWidget {
  final Json goal;
  final String currency;
  const GoalChart({super.key, required this.goal, required this.currency});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.series(context)[0];
    final start = DateTime.parse(goal.s('start_date'));
    final endS = goal.n('end_date');
    final today = DateTime.now();
    final points = goal.l('points');
    final lastPoint = points.isEmpty ? start : DateTime.parse(points.last.s('day'));
    final end = endS != null ? DateTime.parse(endS) : (lastPoint.isAfter(today) ? lastPoint : today);
    final span = max(1, end.difference(start).inDays);
    double x(DateTime d) => d.difference(start).inDays.toDouble().clamp(0, span.toDouble());
    final target = goal.i('target');
    final top = _niceMax(max(target, goal.i('collected')));
    final actual = <FlSpot>[const FlSpot(0, 0)];
    for (final p in points) {
      final d = DateTime.parse(p.s('day'));
      actual.add(FlSpot(x(d), actual.last.y));
      actual.add(FlSpot(x(d), p.i('total').toDouble()));
    }
    final upTo = today.isAfter(end) ? end : today;
    if (!upTo.isBefore(start)) actual.add(FlSpot(x(upTo), actual.last.y));
    final neutral = ChartColors.neutral(context);
    String dayLabel(double v) {
      final d = start.add(Duration(days: v.round()));
      return '${d.day} ${Dates.monthShort(d.month)}';
    }

    return ChartCard(
      title: 'Planned vs real',
      subtitle: endS == null ? 'No end date, so there is no planned line.' : 'Above the grey line means ahead of plan.',
      legend: _Legend([(c, 'Collected', Money.format(goal.i('collected'), currency)), if (endS != null) (neutral, 'Planned', Money.format(target, currency))]),
      chart: Semantics(
        label: 'Goal chart. Collected ${Money.format(goal.i('collected'), currency)} of ${Money.format(target, currency)}.',
        child: LineChart(LineChartData(
          minX: 0,
          maxX: span.toDouble(),
          minY: 0,
          maxY: top,
          gridData: _grid(context, top / 4),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context,
              interval: top / 4,
              bottomInterval: max(1, span / 3).floorToDouble(),
              bottom: (v, meta) => SideTitleWidget(
                  meta: meta, child: Text(dayLabel(v), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ChartColors.ink(context))))),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('${s.barIndex == 0 ? 'Collected' : 'Planned'} by ${dayLabel(s.x)}\n${Money.format(s.y.round(), currency)}',
                      TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 12)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
                spots: actual,
                color: c,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.10))),
            if (endS != null)
              LineChartBarData(
                  spots: [const FlSpot(0, 0), FlSpot(span.toDouble(), target.toDouble())],
                  color: neutral,
                  barWidth: 2,
                  dashArray: [6, 4],
                  dotData: const FlDotData(show: false)),
          ],
        )),
      ),
    );
  }
}

/// One bar showing how today's savings split: each goal, then money not for any goal.
class AllocationBar extends StatelessWidget {
  final Json allocation;
  final String currency;
  const AllocationBar({super.key, required this.allocation, required this.currency});

  @override
  Widget build(BuildContext context) {
    final colors = ChartColors.series(context);
    final neutral = ChartColors.neutral(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final total = allocation.i('total');
    var goals = allocation.l('goals');
    if (goals.length > 6) {
      final other = goals.skip(5).fold<int>(0, (a, g) => a + g.i('amount'));
      goals = [
        ...goals.take(5),
        {'name': 'Other goals', 'amount': other}
      ];
    }
    final parts = <(Color, String, int)>[
      for (var i = 0; i < goals.length; i++) (colors[i], goals[i].s('name'), goals[i].i('amount')),
      (neutral, 'Not for any goal', allocation.i('not_for_goal')),
    ].where((p) => p.$3 > 0).toList();
    final sum = parts.fold<int>(0, (a, p) => a + p.$3);
    return SaccoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Where our savings are going', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text('All in one savings account. Labels show what each part is for. This cycle only.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(Money.format(total, currency), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (sum > 0)
          Semantics(
            label: parts.map((p) => '${p.$2} ${Money.format(p.$3, currency)}').join(', '),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 18,
                child: Row(children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) Container(width: 2, color: cs.surface),
                    Expanded(flex: max(1, (parts[i].$3 * 1000 / sum).round()), child: Container(color: parts[i].$1)),
                  ],
                ]),
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: p.$1, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(p.$2, style: tt.bodyMedium)),
              Text(Money.format(p.$3, currency), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              SizedBox(
                  width: 48,
                  child: Text('${(p.$3 * 100 / max(1, sum)).round()}%', textAlign: TextAlign.right, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          ),
        if (allocation.i('goal_money_used') > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Withdrawals used ${Money.format(allocation.i('goal_money_used'), currency)} of goal money.',
                style: tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }
}
