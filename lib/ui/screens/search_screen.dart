import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/pages.dart';
import '../../data/api.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

void showSearchScreen(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()));

/// The index: type anything, get pages of the app and live records.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final q = TextEditingController();
  Timer? _debounce;
  List<Json> results = [];
  List<AppPage> pages = [];
  bool busy = false;
  String? error;

  static const _icons = {
    'member': Icons.person,
    'journal': Icons.receipt_long,
    'payment': Icons.payments,
    'loan': Icons.request_quote,
    'meeting': Icons.groups,
    'emergency': Icons.health_and_safety,
    'audit': Icons.policy,
  };

  void onChanged(AppState st, String text) {
    _debounce?.cancel();
    setState(() => pages = searchPages(text, st.canSee));
    _debounce = Timer(const Duration(milliseconds: 350), () => search(st, text));
  }

  Future<void> search(AppState st, String text) async {
    if (text.trim().length < 2) {
      setState(() => results = []);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await st.api.search(st.orgId, text.trim());
      if (mounted && q.text == text) setState(() => results = r);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void open(AppState st, Json r) {
    switch (r.s('kind')) {
      case 'member':
        st.goTo(AppPage.statements, memberId: r.s('id'));
      case 'journal':
        st.goTo(AppPage.ledger, tab: 0);
      case 'payment':
        st.goTo(st.canSee(AppPage.approvals) ? AppPage.approvals : AppPage.channels);
      case 'loan':
        st.goTo(AppPage.loans);
      case 'meeting':
        st.goTo(AppPage.meetings);
      case 'emergency':
        st.goTo(AppPage.emergency);
      case 'audit':
        st.goTo(AppPage.ledger, tab: 2);
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final empty = q.text.trim().length >= 2 && results.isEmpty && pages.isEmpty && !busy;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: TextField(
          controller: q,
          autofocus: true,
          style: TextStyle(color: cs.onPrimary),
          cursorColor: cs.secondary,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Name, MoMo ID, loan number, meeting...',
            hintStyle: TextStyle(color: cs.onPrimary.withValues(alpha: 0.7)),
          ),
          onChanged: (t) => onChanged(st, t),
        ),
      ),
      body: ListView(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error!, style: TextStyle(color: cs.error)),
            ),
          if (empty) const Padding(padding: EdgeInsets.all(16), child: EmptyNote('Nothing found. Try fewer letters, or a phone number or transaction ID.')),
          for (final p in pages)
            ListTile(
              leading: Icon(Icons.apps, color: cs.secondary),
              title: Text(st.t(p.title)),
              subtitle: Text(p.hint),
              onTap: () {
                st.goTo(p);
                Navigator.pop(context);
              },
            ),
          if (pages.isNotEmpty && results.isNotEmpty) const Divider(),
          for (final r in results)
            ListTile(
              leading: Icon(_icons[r.s('kind')] ?? Icons.article, color: cs.primary),
              title: Text(r.s('title'), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${r.s('subtitle')}\n${Dates.day(r['at'])}', maxLines: 3, overflow: TextOverflow.ellipsis),
              onTap: () => open(st, r),
            ),
        ],
      ),
    );
  }
}
