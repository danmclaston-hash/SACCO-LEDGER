import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../../core/json.dart';
import '../../core/money.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text.dart';

/// For a circle admin: lets the platform team look inside this circle for a short time. Closed unless the admin opens it.
/// Why: the team that runs the app should not read a group's members or money unless the group asks for help.
class SupportAccessCard extends StatefulWidget {
  const SupportAccessCard({super.key});

  @override
  State<SupportAccessCard> createState() => _SupportAccessCardState();
}

class _SupportAccessCardState extends State<SupportAccessCard> {
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Loaded<Json>(
      key: ValueKey('support-$_n-${st.orgId}'),
      load: () => st.api.supportWindowStatus(st.orgId),
      waiting: const SizedBox.shrink(),
      error: (_) => const SizedBox.shrink(),
      builder: (context, s) {
        final open = s.b('open');
        Future<void> run(Future<void> Function() f, String done) async {
          if (await runAndTell(context, f, done: done)) setState(() => _n++);
        }

        return SaccoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(open ? Icons.visibility_rounded : Icons.lock_rounded, color: open ? SaccoLook.of(context).warn : cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text('Help from the platform team', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Text(
              open
                  ? 'The platform team can look at this circle until ${Dates.dayTime(s['expires_at'])}. They can only look. They cannot change anything. Every look is written in your record.'
                  : 'Closed. The platform team sees only totals, like how many members you have. Nobody can see your names, phones or money unless you open this.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (open)
              OutlinedButton.icon(
                  onPressed: () => run(() => st.api.closeSupportWindow(st.orgId), 'Closed. The platform team is locked out.'),
                  icon: const Icon(Icons.lock_rounded),
                  label: const Text('Close now'))
            else
              FilledButton.icon(
                  onPressed: () => run(() => st.api.openSupportWindow(st.orgId), 'Open for 24 hours.'),
                  icon: const Icon(Icons.support_agent_rounded),
                  label: const Text('Let support look (24 hours)')),
          ]),
        );
      },
    );
  }
}
