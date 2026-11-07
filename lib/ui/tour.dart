import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// First-time welcome tour. Skip = never again. Later = again next time the app opens.
/// Replay any time from My Account → Look and language.
class _Slide {
  final IconData icon;
  final String title;
  final String text;
  const _Slide(this.icon, this.title, this.text);
}

const _slides = [
  _Slide(Icons.account_balance, 'Welcome to SACCO Ledger',
      'Your group\'s money book on the phone. We never hold your money. We keep honest records that nobody can quietly change.'),
  _Slide(Icons.phone_android, 'Pay, then record',
      'Pay your group\'s own MTN, Airtel or bank account. Then record it in Channels. A second person checks it before it counts.'),
  _Slide(Icons.menu_book, 'The ledger cannot be edited',
      'Every shilling is written in the ledger and sealed. Mistakes get a visible correction, never a secret delete. Anyone can run the tamper check.'),
  _Slide(Icons.request_quote, 'Loans and share-out',
      'Borrow up to your loan limit. At the end of the cycle, share-out pays everyone back their savings plus their part of the profit.'),
  _Slide(Icons.info_outline, 'Not sure what a word means?',
      'Tap the small (i) next to it. You can switch these off, change language, text size and theme in My Account.'),
];

/// Shows the tour once, after the first screen appears.
class TourGate extends StatefulWidget {
  final Widget child;
  const TourGate({super.key, required this.child});
  @override
  State<TourGate> createState() => _TourGateState();
}

class _TourGateState extends State<TourGate> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    if (!_shown && !st.tourDone && !st.tourLater) {
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showTour(context);
      });
    }
    return widget.child;
  }
}

Future<void> showTour(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TourDialog(),
    );

class _TourDialog extends StatefulWidget {
  const _TourDialog();
  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  final pages = PageController();
  int i = 0;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void _finish({required bool done}) {
    final st = StateScope.of(context);
    if (done) {
      st.updatePrefs(tourDone: true);
    } else {
      st.tourLaterThisTime();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final last = i == _slides.length - 1;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${i + 1} of ${_slides.length}', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                TextButton(onPressed: () => _finish(done: true), child: const Text('Skip')),
              ]),
              Expanded(
                child: PageView.builder(
                  controller: pages,
                  itemCount: _slides.length,
                  onPageChanged: (v) => setState(() => i = v),
                  itemBuilder: (_, k) {
                    final s = _slides[k];
                    return SingleChildScrollView(
                      child: Column(children: [
                        const SizedBox(height: 8),
                        CircleAvatar(radius: 40, backgroundColor: cs.primaryContainer, child: Icon(s.icon, size: 40, color: saccoEmerald)),
                        const SizedBox(height: 20),
                        Text(s.title, textAlign: TextAlign.center, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(s.text, textAlign: TextAlign.center, style: tt.bodyLarge),
                      ]),
                    );
                  },
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var k = 0; k < _slides.length; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
                    width: k == i ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(color: k == i ? cs.primary : cs.outlineVariant, borderRadius: BorderRadius.circular(4)),
                  ),
              ]),
              Row(children: [
                TextButton(onPressed: () => _finish(done: false), child: const Text('Later')),
                const Spacer(),
                if (i > 0)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                    icon: const Icon(Icons.arrow_back),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: last ? () => _finish(done: true) : () => pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Text(last ? 'Start' : 'Next'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
