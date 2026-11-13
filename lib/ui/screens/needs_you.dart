import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/pages.dart';
import '../theme.dart';
import '../tour.dart';
import '../widgets.dart';
import 'two_step.dart';
import '../text.dart';

/// One thing that needs the person, as one tappable line.
class _Todo {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool urgent;
  const _Todo(this.icon, this.text, this.onTap, {this.urgent = false});
}

/// The top of every home page: a short list of what needs this person now, most urgent first.
/// Everything else on the page can wait. When nothing needs them, officers see "All done" and members see nothing.
class NeedsYouCard extends StatelessWidget {
  const NeedsYouCard({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final d = st.dash;
    final officer = st.role.isOfficer && st.role != Role.platformAdmin;
    final admin = st.role == Role.orgAdmin && !(st.org?.b('is_demo') ?? false);
    final late = st.loans.where((l) => l.s('status') == 'active' && l.i('arrears_days') > 0).length;
    final open = st.openMeeting;
    final n = st.invites.length;

    final todos = <_Todo>[
      if (st.platformNeedsTwoStep)
        _Todo(Icons.shield_rounded, 'Turn on two-step sign-in to unlock platform tools', () => showTwoStepSetup(context), urgent: true),
      if (open != null) _Todo(Icons.groups_rounded, 'Meeting #${open.i('meeting_number')} is open now', () => st.goTo(AppPage.meetings), urgent: true),
      if (officer && d.i('pending_payments') > 0)
        _Todo(Icons.fact_check_rounded, '${_count(d.i('pending_payments'), 'payment')} to check', () => st.goTo(AppPage.approvals), urgent: true),
      if (officer && d.i('pending_loans') > 0)
        _Todo(Icons.request_quote_rounded, '${_count(d.i('pending_loans'), 'loan request')} waiting', () => st.goTo(AppPage.loans)),
      if (officer && d.i('pending_emergency') > 0)
        _Todo(Icons.health_and_safety_rounded, '${_count(d.i('pending_emergency'), 'emergency claim')} waiting', () => st.goTo(AppPage.emergency)),
      if (officer && late > 0) _Todo(Icons.schedule_rounded, '${_count(late, 'loan')} late', () => st.goTo(AppPage.loans)),
      if (n > 0)
        _Todo(Icons.mark_email_unread_rounded, n == 1 ? '${st.invites.first.s('org_name')} invited you to join' : '$n circles invited you to join',
            () => st.goTo(AppPage.circles)),
      if (st.role == Role.platformAdmin)
        _Todo(Icons.visibility_rounded, 'You are only looking at this circle. Its admin runs it.', () => st.goTo(AppPage.circles)),
    ];

    final rows = <Widget>[
      for (final t in todos) _Row(t),
      if (admin) const _PlatformAsks(),
    ];
    if (rows.isEmpty && !officer) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    return TourTarget.needs.wrap(SaccoCard(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(todos.isEmpty ? 'Today' : 'Needs you', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        ),
        if (todos.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, color: look.ok),
              const SizedBox(width: 10),
              Expanded(child: Text('All done. Nothing needs you right now.', style: tt.bodyLarge)),
            ]),
          ),
        ...rows,
      ]),
    ));
  }
}

String _count(int n, String thing) => '$n ${n == 1 ? thing : '${thing}s'}';

class _Row extends StatelessWidget {
  final _Todo t;
  const _Row(this.t);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final look = SaccoLook.of(context);
    final (Color bg, Color fg) = t.urgent ? (look.accent, look.onAccent) : (cs.surfaceContainerHighest, cs.onSurface);
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(look.radius * 0.6)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(look.isPassbook ? 4 : 12)),
        child: Icon(t.icon, color: fg, size: 22),
      ),
      title: Text(t.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      onTap: t.onTap,
    );
  }
}

/// For a circle admin: the platform team asked to invite someone, and only the admin can say yes.
class _PlatformAsks extends StatelessWidget {
  const _PlatformAsks();

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return Loaded<List<Json>>(
      load: () => st.api.circleInvites(st.orgId),
      waiting: const SizedBox.shrink(),
      error: (_) => const SizedBox.shrink(),
      builder: (context, list) {
        final w = list.where((x) => x.s('status') == 'awaiting_circle').length;
        if (w == 0) return const SizedBox.shrink();
        return _Row(_Todo(
            Icons.how_to_reg_rounded, 'The platform team asks to invite ${w == 1 ? 'someone' : '$w people'}. You decide.', () => st.goTo(AppPage.members),
            urgent: true));
      },
    );
  }
}
