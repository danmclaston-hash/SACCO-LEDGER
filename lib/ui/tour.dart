import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/pages.dart';
import 'theme.dart';
import 'widgets.dart';

/// The parts of the app the tour can point at. Each screen tags its widget with `TourTarget.x.wrap(child)`.
/// A step whose part is not on screen (for example a member has no "Record" row) is skipped, so one tour fits every role.
enum TourTarget {
  circle,
  search,
  needs,
  money,
  actions,
  tabs;

  static final Map<TourTarget, GlobalKey> _keys = {for (final t in TourTarget.values) t: GlobalKey(debugLabel: 'tour-${t.name}')};

  GlobalKey get key => _keys[this]!;

  Widget wrap(Widget child) => KeyedSubtree(key: key, child: child);

  Rect? get rect {
    final ctx = key.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class _Step {
  final TourTarget? target;
  final IconData icon;
  final String title;
  final String text;
  final bool tap;
  const _Step(this.target, this.icon, this.title, this.text, {this.tap = false});
}

const _steps = [
  _Step(null, Icons.account_balance, 'Welcome to SACCO Ledger',
      'Let us walk you through. It takes one minute. We never hold your money. We keep honest records that nobody can quietly change.'),
  _Step(TourTarget.circle, Icons.diversity_3_rounded, 'Your circle', 'This is the group you are in. Tap it to switch to another circle.', tap: true),
  _Step(TourTarget.needs, Icons.notifications_active_rounded, 'What needs you',
      'Things waiting for you show up here. Tap one to go straight to it. When it says All done, you can relax.'),
  _Step(TourTarget.money, Icons.savings_rounded, 'Your money, one look', 'Here is the money at a glance. Tap it to see more.'),
  _Step(TourTarget.actions, Icons.touch_app_rounded, 'Your big buttons',
      'The things you do most are here. To pay: pay your group\'s own account first, then record it. A second person checks it.',
      tap: true),
  _Step(TourTarget.tabs, Icons.apps_rounded, 'Move around', 'These buttons take you to the main pages. "More" opens everything else.', tap: true),
  _Step(TourTarget.search, Icons.search_rounded, 'Find anything', 'Looking for a person, a payment or a record? Search finds it.', tap: true),
  _Step(null, Icons.verified_rounded, 'You are ready',
      'Every shilling is written in the ledger and sealed. Mistakes get a visible correction, never a secret delete. Tap the small (i) beside any word you do not know. You can replay this tour in My Account.'),
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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Let the home page finish drawing so every part has a place to point at.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) showTour(this.context);
      });
    }
    return widget.child;
  }
}

OverlayEntry? _open;

/// Starts the spotlight tour on top of the current screen.
void showTour(BuildContext context) {
  if (_open != null) return;
  final st = StateScope.of(context);
  if (st.page != AppPage.overview) st.goTo(AppPage.overview);
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  void close() {
    entry.remove();
    entry.dispose();
    _open = null;
  }

  entry = OverlayEntry(builder: (_) => _Spotlight(onClose: close, state: st));
  _open = entry;
  overlay.insert(entry);
}

class _Spotlight extends StatefulWidget {
  final VoidCallback onClose;
  final dynamic state;
  const _Spotlight({required this.onClose, required this.state});
  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  late final AnimationController _hand = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  late List<_Step> _live;
  int _i = 0;
  Rect? _from;
  Rect? _to;
  bool _ready = false;
  bool _calm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _move.dispose();
    _draw.dispose();
    _pulse.dispose();
    _hand.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ready) setState(() => _to = _measure(_live[_i]));
      });

  Rect? _measure(_Step s) {
    final r = s.target?.rect;
    if (r == null) return null;
    final size = MediaQuery.sizeOf(context);
    if (r.width < 4 || r.height < 4 || r.bottom < 0 || r.top > size.height || r.right < 0 || r.left > size.width) return null;
    return r;
  }

  /// Keep only the steps whose part is really on screen.
  void _begin() {
    _live = [
      for (final s in _steps)
        if (s.target == null || s.target!.rect != null) s,
    ];
    _ready = true;
    _go(0, first: true);
  }

  Future<void> _go(int to, {bool first = false}) async {
    if (!mounted) return;
    final s = _live[to];
    final ctx = s.target?.key.currentContext;
    if (ctx != null && !_calm) {
      // Scroll the part into view if it sits below the fold.
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.3);
      if (!mounted) return;
    }
    final size = MediaQuery.sizeOf(context);
    final next = _measure(s);
    setState(() {
      _from = first ? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0) : _current();
      _i = to;
      _to = next;
    });
    if (_calm) {
      _move.value = 1;
      _draw.value = 1;
    } else {
      _move.forward(from: 0);
      _draw.forward(from: 0);
    }
  }

  Rect _empty() => Rect.fromCenter(center: MediaQuery.sizeOf(context).center(Offset.zero), width: 0, height: 0);

  /// Where the hole is right now, mid-move included.
  Rect _current() {
    final a = _from ?? _empty();
    final b = _to ?? _empty();
    return Rect.lerp(a, b, Curves.easeInOutCubic.transform(_move.value)) ?? b;
  }

  void _finish({required bool done}) {
    final st = widget.state;
    if (done) {
      st.updateSettings(tourDone: true);
    } else {
      st.tourLaterThisTime();
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    _calm = MediaQuery.disableAnimationsOf(context);
    if (!_ready) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = SaccoLook.of(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final s = _live[_i];
    final last = _i == _live.length - 1;
    const cardH = 236.0;
    final cardW = math.min(size.width - 32, 420.0);

    // BlockSemantics hides the screen underneath from screen readers and automation, so nothing behind the tour can be pressed.
    return BlockSemantics(
        child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(done: false),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => last ? _finish(done: true) : _go(_i + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _i > 0 ? _go(_i - 1) : null,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: Listenable.merge([_move, _draw, _pulse, _hand]),
            builder: (context, _) {
              final hole = _current();
              final has = _to != null;
              // The card sits below the hole when there is room, otherwise above it. With no hole it sits in the middle.
              final below = hole.bottom + 16 + cardH + pad.bottom < size.height;
              final double top = !has
                  ? (size.height - cardH) / 2
                  : below
                      ? hole.bottom + 20
                      : math.max(pad.top + 8, hole.top - 20 - cardH);
              return Stack(children: [
                // Dim everything, cut a hole, and swallow taps so nothing underneath is pressed by accident.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(
                      painter: _SpotPainter(
                        hole: has ? hole : null,
                        grow: _move.value,
                        draw: _draw.value,
                        pulse: _pulse.value,
                        ring: look.accent,
                        dim: Colors.black.withValues(alpha: 0.74),
                      ),
                    ),
                  ),
                ),
                if (has && s.tap)
                  Positioned(
                    left: hole.center.dx - 18,
                    top: hole.center.dy - 6 + 10 * Curves.easeInOut.transform(_hand.value),
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: _move.value,
                        child: const Icon(Icons.touch_app_rounded, size: 36, color: Colors.white, shadows: [Shadow(blurRadius: 12, color: Colors.black54)]),
                      ),
                    ),
                  ),
                Positioned(
                  left: (size.width - cardW) / 2,
                  top: top,
                  width: cardW,
                  height: cardH,
                  child: Opacity(
                    opacity: Curves.easeOut.transform(_move.value.clamp(0, 1)),
                    child: Transform.translate(
                      offset: Offset(0, (1 - Curves.easeOut.transform(_move.value)) * (below ? 14 : -14)),
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        label: '${s.title}. ${s.text}',
                        child: Material(
                          color: cs.surface,
                          elevation: 10,
                          borderRadius: BorderRadius.circular(look.radius),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                CircleAvatar(radius: 18, backgroundColor: cs.primaryContainer, child: Icon(s.icon, size: 20, color: cs.primary)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(s.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                                Text('${_i + 1}/${_live.length}', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                              ]),
                              const SizedBox(height: 8),
                              Expanded(child: SingleChildScrollView(child: Text(s.text, style: tt.bodyMedium))),
                              Row(children: [
                                for (var k = 0; k < _live.length; k++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    margin: const EdgeInsets.only(right: 4),
                                    width: k == _i ? 18 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: k == _i ? cs.primary : cs.outlineVariant, borderRadius: BorderRadius.circular(3)),
                                  ),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                if (!last) ...[
                                  TextButton(onPressed: () => _finish(done: true), child: const Text('Skip')),
                                  TextButton(onPressed: () => _finish(done: false), child: const Text('Later')),
                                ],
                                const Spacer(),
                                if (_i > 0) IconButton(tooltip: 'Back', onPressed: () => _go(_i - 1), icon: const Icon(Icons.arrow_back)),
                                FilledButton(
                                  onPressed: last ? () => _finish(done: true) : () => _go(_i + 1),
                                  child: Text(last ? 'Start' : 'Next'),
                                ),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    ));
  }
}

/// Dark cover with a rounded hole. A gold ring draws itself round the hole, then pulses softly.
class _SpotPainter extends CustomPainter {
  final Rect? hole;
  final double grow;
  final double draw;
  final double pulse;
  final Color ring;
  final Color dim;
  const _SpotPainter({required this.hole, required this.grow, required this.draw, required this.pulse, required this.ring, required this.dim});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final h = hole;
    if (h == null || h.width < 1 || h.height < 1) {
      canvas.drawRect(full, Paint()..color = dim);
      return;
    }
    final r = h.inflate(8);
    final radius = Radius.circular(math.min(18, math.min(r.width, r.height) / 2));
    final rr = RRect.fromRectAndRadius(r, radius);
    final cover = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRRect(rr);
    canvas.drawPath(cover, Paint()..color = dim);

    // Soft glow just outside the hole.
    canvas.drawRRect(
        rr,
        Paint()
          ..color = ring.withValues(alpha: 0.35 * grow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // The ring draws itself, clockwise from the top.
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      canvas.drawPath(
          m.extractPath(0, m.length * Curves.easeOutCubic.transform(draw)),
          Paint()
            ..color = ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
    }

    // A ring that breathes outward and fades.
    final out = RRect.fromRectAndRadius(r.inflate(4 + 16 * pulse), Radius.circular(radius.x + 4 + 16 * pulse));
    canvas.drawRRect(
        out,
        Paint()
          ..color = ring.withValues(alpha: (1 - pulse) * 0.55 * draw)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_SpotPainter old) => old.hole != hole || old.grow != grow || old.draw != draw || old.pulse != pulse || old.ring != ring || old.dim != dim;
}
