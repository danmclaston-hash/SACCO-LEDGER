import 'package:flutter/material.dart';

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/pages.dart';
import '../motion.dart';
import '../theme.dart';
import '../tour.dart';
import '../widgets.dart';

/// A member's home: their money, four big picture buttons, and the state of their last payment.
/// Built so a person who reads little can still find their way by picture and colour.
class MemberHome extends StatelessWidget {
  const MemberHome({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final me = st.me;
    final first = (me?.s('full_name') ?? st.account.s('full_name')).trim().split(' ').first;
    final goal = st.activeGoals.firstOrNull;
    final mine = st.payments.where((p) => p.s('member_id') == st.myMemberId).toList();
    final last = mine.firstOrNull;
    final waiting = mine.where((p) => p.s('status') == 'pending').length;

    return AppPageView(
      children: [
        RiseIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(first.isEmpty ? st.t('Home') : 'Hello, $first', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (st.org!.b('is_demo')) Padding(padding: const EdgeInsets.only(top: 6), child: Pill(text: 'DEMO DATA: not real money', color: look.warn)),
            ],
          ),
        ),
        RiseIn(
          delay: const Duration(milliseconds: 60),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: look.brand, borderRadius: BorderRadius.circular(look.radius)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(st.t('My savings'), style: tt.bodyMedium?.copyWith(color: look.onBrandMuted)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(context, me?.i('savings') ?? 0),
                    style: look.numbers(tt.displaySmall).copyWith(color: look.onBrand, fontWeight: FontWeight.w700, fontSize: 34),
                  ),
                ),
                if (goal != null) ...[
                  const SizedBox(height: 16),
                  _GoalStrip(goal),
                ],
              ],
            ),
          ),
        ),
        RiseIn(
          delay: const Duration(milliseconds: 120),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _BigTile(width: w, icon: Icons.arrow_circle_up_rounded, label: st.t('Pay'), main: true, onTap: () => st.goTo(AppPage.channels)),
                  _BigTile(width: w, icon: Icons.account_balance_wallet_outlined, label: st.t('My money'), onTap: () => st.goTo(AppPage.statements)),
                  _BigTile(width: w, icon: Icons.payments_outlined, label: st.t('Loans'), onTap: () => st.goTo(AppPage.loans)),
                  _BigTile(width: w, icon: Icons.help_outline_rounded, label: st.t('Help'), onTap: () => showHelp(context)),
                ],
              );
            },
          ),
        ),
        if (last != null)
          RiseIn(
            delay: const Duration(milliseconds: 180),
            child: _LastPayment(last, waiting: waiting),
          ),
        if (last == null)
          Text('When you pay, your record shows here with a green tick once it is checked.', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _GoalStrip extends StatelessWidget {
  final Json goal;
  const _GoalStrip(this.goal);
  @override
  Widget build(BuildContext context) {
    final look = SaccoLook.of(context);
    final tt = Theme.of(context).textTheme;
    final target = goal.i('target');
    final part = target <= 0 ? 0.0 : (goal.i('collected') / target).clamp(0.0, 1.0);
    final pct = (part * 100).round();
    return Semantics(
      label: '${goal.s('name')}: $pct percent of the goal',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 16, color: look.onBrandMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(goal.s('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: look.onBrandMuted))),
                Text('$pct%', style: look.numbers(tt.bodySmall).copyWith(color: look.onBrand, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(look.isPassbook ? 1 : 4),
              child: LinearProgressIndicator(
                  value: part, minHeight: 8, backgroundColor: look.onBrand.withValues(alpha: 0.16), color: look.isPassbook ? look.onBrand : look.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final bool main;
  final VoidCallback onTap;
  const _BigTile({required this.width, required this.icon, required this.label, required this.onTap, this.main = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final look = SaccoLook.of(context);
    // The one filled tile is the thing most people came to do.
    final (Color bg, Color fg) = main ? (look.isPassbook ? (cs.primary, cs.onPrimary) : (look.accent, look.onAccent)) : (cs.surface, cs.primary);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(look.radius),
      side: main ? BorderSide.none : BorderSide(color: look.isPassbook ? cs.primary : cs.outlineVariant, width: 1.5),
    );
    return SizedBox(
      width: width,
      height: 124,
      child: Material(
        color: bg,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 40, color: fg),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Green tick: a second person checked it. Clock: still waiting. Cross: sent back.
class _LastPayment extends StatelessWidget {
  final Json p;
  final int waiting;
  const _LastPayment(this.p, {required this.waiting});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final (IconData icon, Color fg, Color bg, String line) = switch (p.s('status')) {
      'confirmed' => (Icons.check_rounded, look.ok, look.okBg, 'Checked and in the book'),
      'pending' => (Icons.schedule_rounded, look.warn, cs.surfaceContainerHighest, 'Waiting for the treasurer to check'),
      'rejected' => (Icons.close_rounded, cs.error, cs.errorContainer, 'Sent back. Tap to see why'),
      _ => (Icons.undo_rounded, cs.onSurfaceVariant, cs.surfaceContainerHighest, p.s('status').replaceAll('_', ' ')),
    };
    return SaccoCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(look.radius),
        onTap: () => st.goTo(AppPage.channels),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: fg, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${money(context, p.i('amount'))} • ${Purpose.labelOf(p.s('purpose'))}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(waiting > 1 ? '$line. $waiting records waiting' : line, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short picture steps for paying, a way to reach the treasurer, and the tour.
Future<void> showHelp(BuildContext context) {
  final st = StateScope.of(context);
  final officer = st.members.where((m) => m.b('is_active') && Role.parse(m.s('role')).handlesMoney && (m.n('phone') ?? '').isNotEmpty).firstOrNull;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final tt = Theme.of(ctx).textTheme;
      Widget step(int n, IconData icon, String text) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                CircleAvatar(radius: 22, backgroundColor: cs.primaryContainer, child: Icon(icon, color: cs.onPrimaryContainer)),
                const SizedBox(width: 14),
                Expanded(child: Text('$n. $text', style: tt.bodyLarge)),
              ],
            ),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('How to pay', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              step(1, Icons.phone_android, 'Send the money to your group with mobile money, as you always do.'),
              step(2, Icons.sms_outlined, 'You get an SMS. It has a transaction ID.'),
              step(3, Icons.arrow_circle_up_rounded, 'Tap Pay, then Record a Payment. Type the amount and the ID.'),
              step(4, Icons.check_circle_outline, 'The treasurer checks it. You see a green tick.'),
              const SizedBox(height: 4),
              Text('The app only writes things down. It never holds your money.', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (officer != null)
                FilledButton.icon(
                  onPressed: () => openOrCopy(ctx, Uri.parse('tel:${officer.s('phone')}'),
                      copy: officer.s('phone'), failMessage: 'Could not open the dialer. Number copied.'),
                  icon: const Icon(Icons.call),
                  label: Text('Call ${officer.s('full_name').split(' ').first} (${Role.labelOf(officer.s('role'))})'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showTour(context);
                },
                icon: const Icon(Icons.slideshow),
                label: const Text('Show me around the app'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
