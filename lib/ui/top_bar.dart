import 'package:flutter/material.dart' hide Text, InputDecoration;

import '../core/catalog.dart';
import '../core/pages.dart';
import '../core/json.dart';
import 'screens/account_screen.dart';
import 'screens/circles_screen.dart' show withArticle;
import 'screens/search_screen.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';
import 'text.dart';

/// Same top bar as the original app. The role pill now shows your real role:
/// a person cannot switch themselves into treasurer any more.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final tt = Theme.of(context).textTheme;
    final org = st.org;
    final look = SaccoLook.of(context);
    // Narrow screens keep only what is needed: the group, search and the person. The rest lives in My Account.
    final roomy = MediaQuery.sizeOf(context).width >= 600;
    return Material(
      color: look.brand,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              if (Scaffold.maybeOf(context)?.hasDrawer ?? false)
                IconButton(
                  icon: Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              Expanded(
                child: PopupMenuButton<Json>(
                  tooltip: tr('Switch circle'),
                  onSelected: (o) => o.isEmpty ? st.goTo(AppPage.circles) : st.selectOrg(o),
                  itemBuilder: (_) => [
                    // My own circles first. The platform team's look-only circles follow.
                    for (final o in [...st.myCircles, ...st.lookOnlyCircles])
                      PopupMenuItem(
                        value: o,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.s('name'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                                '${switch (Role.parse(o.s('my_role'))) {
                                  Role.orgAdmin => 'Admin',
                                  Role.platformAdmin => 'Look only',
                                  final r => r.short
                                }} • ${o.s('currency_code')}',
                                style: tt.bodySmall),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem<Json>(
                      value: const {},
                      child: Row(children: [
                        const Icon(Icons.diversity_3_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(st.invites.isEmpty ? 'My circles' : 'My circles (${st.invites.length} new)', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                  child: TourTarget.circle.wrap(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance, size: 20, color: look.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              org?.s('name') ?? 'SACCO Ledger',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(org == null ? '' : 'You are ${st.role == Role.platformAdmin ? 'looking only' : withArticle(st.role)}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelSmall?.copyWith(color: look.onBrandMuted)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  )),
                ),
              ),
              IconButton(
                key: TourTarget.search.key,
                tooltip: tr('Search everything'),
                icon: Icon(Icons.search, color: Colors.white),
                onPressed: () => showSearchScreen(context),
              ),
              if (roomy) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: look.accent, borderRadius: BorderRadius.circular(look.isPassbook ? 4 : 12)),
                  child: Text(
                    st.currency,
                    style: tt.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: look.onAccent),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(look.isPassbook ? 4 : 16)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.badge, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(st.role.short, style: tt.labelMedium?.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ],
              IconButton(
                tooltip: st.t(AppPage.account.title),
                onPressed: () => st.goTo(AppPage.account),
                icon: Avatar(name: st.account.s('full_name').isEmpty ? '?' : st.account.s('full_name'), photo: st.account['avatar'] as String?, size: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
