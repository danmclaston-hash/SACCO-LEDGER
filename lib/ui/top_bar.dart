import 'package:flutter/material.dart';

import '../core/search_index.dart';
import '../core/json.dart';
import 'screens/account_screen.dart';
import 'screens/search_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Same top bar as the original app. The role pill now shows your real role:
/// a person cannot switch themselves into treasurer any more.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final org = st.org;
    // Brand bar stays emerald in light and dark, with white text, like the original app.
    return Material(
      color: saccoEmerald,
      elevation: 4,
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
                  tooltip: 'Switch group',
                  onSelected: st.selectOrg,
                  itemBuilder: (_) => [
                    for (final o in st.orgs)
                      PopupMenuItem(
                        value: o,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.s('name'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${editionNames[o.s('edition')]} • ${o.s('currency_code')}', style: tt.bodySmall),
                          ],
                        ),
                      ),
                  ],
                  child: Row(
                    children: [
                      Icon(Icons.account_balance, size: 20, color: cs.secondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              org?.s('name') ?? 'SACCO Ledger',
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(editionNames[org?.s('edition')]?.split(':').first ?? 'Community Group', style: tt.labelSmall?.copyWith(color: cs.secondary)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Search everything',
                icon: Icon(Icons.search, color: Colors.white),
                onPressed: () => showSearchScreen(context),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: cs.secondary, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  st.currency,
                  style: tt.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(_short[st.role] ?? st.role, style: tt.labelMedium?.copyWith(color: Colors.white)),
                  ],
                ),
              ),
              // Language, theme and the rest now live in My Account, opened from your picture.
              IconButton(
                tooltip: st.t('my_account'),
                onPressed: () => st.goTo(AppPage.account),
                icon: Avatar(name: st.account.s('full_name').isEmpty ? '?' : st.account.s('full_name'), photo: st.account['avatar'] as String?, size: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _short = {
    'org_admin': 'Org Admin',
    'loan_officer': 'Loan Officer',
    'platform_admin': 'Platform',
    'treasurer': 'Treasurer',
    'secretary': 'Secretary',
    'auditor': 'Auditor',
    'member': 'Member',
  };
}
