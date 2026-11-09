import 'package:flutter/material.dart';

import 'theme.dart';

bool _still(BuildContext c) => MediaQuery.disableAnimationsOf(c);

/// Slides a child up and fades it in once, after [delay]. Does nothing when the phone asks for less motion.
class RiseIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  const RiseIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  Widget build(BuildContext context) {
    if (_still(context)) return child;
    const run = Duration(milliseconds: 450);
    final total = run + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (_, v, child) {
        final t = Curves.easeOutCubic.transform(((v * total.inMilliseconds - delay.inMilliseconds) / run.inMilliseconds).clamp(0.0, 1.0));
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child));
      },
      child: child,
    );
  }
}

/// Two slow rings that grow out of a round button, to say "touch here".
class PulseRing extends StatefulWidget {
  final Widget child;
  final double size;
  final Color color;
  const PulseRing({super.key, required this.child, required this.size, required this.color});
  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget ring(double shift) => AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = (_c.value + shift) % 1.0;
            return Transform.scale(
              scale: 1 + 0.5 * t,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color.withValues(alpha: 0.55 * (1 - t)), width: 2)),
              ),
            );
          },
        );
    return SizedBox(
      width: widget.size * 1.5,
      height: widget.size * 1.5,
      child: Stack(alignment: Alignment.center, children: [
        if (!_still(context)) ...[ring(0), ring(0.5)],
        widget.child
      ]),
    );
  }
}

/// The app's mark and name at the top of the sign-in screen, arriving one after the other.
class BrandHeader extends StatelessWidget {
  final String title;
  final String line;
  const BrandHeader({super.key, required this.title, required this.line});

  @override
  Widget build(BuildContext context) {
    final look = SaccoLook.of(context);
    final tt = Theme.of(context).textTheme;
    final mark = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: look.accent, borderRadius: BorderRadius.circular(look.isPassbook ? 6 : 18)),
      child: Icon(Icons.account_balance, size: 34, color: look.onAccent),
    );
    return Column(
      crossAxisAlignment: look.isPassbook ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        RiseIn(child: mark),
        const SizedBox(height: 16),
        RiseIn(
          delay: const Duration(milliseconds: 80),
          child: Text(title, style: tt.headlineSmall?.copyWith(color: look.onBrand, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 2),
        RiseIn(
          delay: const Duration(milliseconds: 140),
          child: Text(line, style: tt.bodyMedium?.copyWith(color: look.onBrandMuted)),
        ),
      ],
    );
  }
}
