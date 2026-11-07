import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/catalog.dart';
import '../core/glossary.dart';
import '../core/json.dart';
import '../core/money.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Lets any screen reach the app state.
class StateScope extends InheritedNotifier<AppState> {
  const StateScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<StateScope>()!.notifier!;
}

void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
}

/// Runs a change from a dialog: keeps it open and shows the reason if the rules refuse.
Future<void> runAndClose(BuildContext dialogCtx, AppState st, Future<void> Function() fn, {String? done}) async {
  final nav = Navigator.of(dialogCtx);
  final messenger = ScaffoldMessenger.of(dialogCtx);
  final outer = ScaffoldMessenger.of(nav.context);
  final errColor = Theme.of(dialogCtx).colorScheme.error;
  final err = await st.act(fn);
  if (err != null) {
    messenger.showSnackBar(SnackBar(content: Text(err), backgroundColor: errColor, duration: const Duration(seconds: 6)));
  } else {
    nav.pop();
    if (done != null) outer.showSnackBar(SnackBar(content: Text(done)));
  }
}

/// Runs a change from a page and says how it went: [done] if fine, the rule's reason if refused.
Future<bool> runAndTell(BuildContext context, Future<void> Function() fn, {String? done}) async {
  final err = await StateScope.of(context).act(fn);
  if (context.mounted && (err != null || done != null)) showMsg(context, err ?? done!, error: err != null);
  return err == null;
}

/// Opens a link or the phone dialer. If the phone cannot, copies it so the person can paste it.
Future<void> openOrCopy(BuildContext context, Uri uri, {required String copy, required String failMessage, bool external = false}) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault);
  } catch (_) {}
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: copy));
  if (context.mounted) showMsg(context, failMessage);
}

/// Fetches extra data for one part of a page, with the usual spinner and error.
/// Fetches again after every reload of the app's data, and when [id] changes. Never just because the page redrew.
class Loaded<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? id;

  /// What shows while loading, and instead of an error. A spinner and the error text unless given.
  final Widget? waiting;
  final Widget Function(Object error)? error;
  const Loaded({super.key, required this.load, required this.builder, this.id, this.waiting, this.error});

  @override
  State<Loaded<T>> createState() => _LoadedState<T>();
}

class _LoadedState<T> extends State<Loaded<T>> {
  String? _for;
  late Future<T> _future;

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final key = '${st.orgId}-${st.version}-${widget.id}';
    if (key != _for) {
      _for = key;
      _future = widget.load();
    }
    // A new reload keeps showing the old numbers until the new ones arrive; another group or [id] starts clean.
    return FutureBuilder<T>(
      key: ValueKey('${st.orgId}-${widget.id}'),
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          if (widget.error != null) return widget.error!(snap.error!);
          return Padding(padding: const EdgeInsets.all(16), child: Text(snap.error.toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)));
        }
        if (!snap.hasData) return widget.waiting ?? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

class AppPageView extends StatelessWidget {
  final List<Widget> children;
  const AppPageView({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    return RefreshIndicator(
      onRefresh: st.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (st.offline)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Pill(text: 'Offline: showing the last saved records', color: warnOrange),
              ),
            ),
          if (st.loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(st.loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 16), child: c),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  /// A glossary word (see core/glossary.dart). Adds an (i) button that explains it.
  final String? info;
  const SectionTitle(this.text, {super.key, this.trailing, this.info});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              if (info != null) InfoTip(info!),
            ]),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

/// Small (i) button. Tap it to read what a word means. Hidden when "Explain words" is off in My Account.
class InfoTip extends StatelessWidget {
  final String term;
  const InfoTip(this.term, {super.key});
  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final t = glossary[term];
    if (!st.showTips || t == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'What is ${t.title.toLowerCase()}?',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: Icon(Icons.info_outline, color: cs.primary),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, color: cs.primary),
                const SizedBox(width: 8),
                Text(t.title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              Text(t.text, style: Theme.of(ctx).textTheme.bodyLarge),
              const SizedBox(height: 16),
              Text('You can hide these (i) buttons in My Account → Look and language.',
                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class SaccoCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double radius;
  final double elevation;
  final EdgeInsets padding;
  const SaccoCard({super.key, required this.child, this.color, this.radius = 16, this.elevation = 0, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        color: color ?? Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: elevation,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        child: Padding(padding: padding, child: child),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color foreground;
  const Pill({super.key, required this.text, required this.color, this.foreground = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: foreground),
        ),
      );
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      'confirmed' || 'paid' || 'closed' => (okGreenBg, okGreen),
      'active' || 'open' => (okGreen, Colors.white),
      'approved' => (saccoEmeraldLight, Colors.white),
      'pending' || 'pending_approval' || 'waiting' || 'needs_review' => (warnOrange, Colors.white),
      'rejected' || 'reversed' || 'failed' => (cs.error, cs.onError),
      _ => (Colors.grey, Colors.white),
    };
    return Pill(text: status.replaceAll('_', ' ').toUpperCase(), color: bg, foreground: fg);
  }
}

class BalanceStatCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final IconData icon;
  final Color color;
  const BalanceStatCard({super.key, required this.title, required this.amount, required this.subtitle, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SaccoCard(
      color: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                ),
              ),
              Icon(icon, size: 18, color: cs.primary),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class KeyValue extends StatelessWidget {
  final String k;
  final String v;
  const KeyValue(this.k, this.v, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(child: Text(v, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );
}

/// Choose a member from the group.
class MemberPicker extends StatelessWidget {
  final String label;
  final String? value;
  final List<Json> members;
  final ValueChanged<String?> onChanged;
  const MemberPicker({super.key, required this.label, required this.value, required this.members, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: members.any((m) => m.s('id') == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final m in members)
            DropdownMenuItem(
              value: m.s('id'),
              child: Text('${m.s('full_name')} (${Role.labelOf(m.s('role'))})', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      );
}

/// Small square in the brand colour, with the official logo if its file is in assets/brands/.
class BrandMark extends StatelessWidget {
  final String channel;
  final double size;
  const BrandMark(this.channel, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) {
    final b = brands[channel];
    if (b == null) return SizedBox(width: size, height: size);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: b.color, borderRadius: BorderRadius.circular(size / 4)),
      child: Icon(b.icon, size: size * 0.62, color: b.onColor),
    );
    if (b.logo == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.asset(b.logo!, width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// Channel name with its brand mark, e.g. on a payment record.
class BrandChip extends StatelessWidget {
  final String channel;
  const BrandChip(this.channel, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        BrandMark(channel, size: 16),
        const SizedBox(width: 6),
        Text(Channel.labelOf(channel), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ]);
}

/// Big button in the network's own colours, e.g. "MTN MoMo".
class BrandButton extends StatelessWidget {
  final String channel;
  final String label;
  final VoidCallback? onPressed;
  const BrandButton({super.key, required this.channel, required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final b = brands[channel]!;
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: b.color, foregroundColor: b.onColor, minimumSize: const Size(64, 48)),
      onPressed: onPressed,
      icon: BrandMark(channel, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

/// How the money moved, and its transaction ID unless it was cash.
class ChannelFields extends StatelessWidget {
  final Channel value;
  final ValueChanged<Channel> onChanged;
  final TextEditingController ref;
  const ChannelFields({super.key, required this.value, required this.onChanged, required this.ref});

  /// The ID to send: none for cash.
  static String? refFor(Channel c, TextEditingController ref) => c.needsRef ? ref.text.trim() : null;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<Channel>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'How the money moved'),
          items: [
            for (final c in Channel.byHand)
              DropdownMenuItem(value: c, child: Row(children: [BrandMark(c.code), const SizedBox(width: 10), Text(c.label)])),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
        if (value.needsRef) ...[
          gap,
          TextField(
            controller: ref,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Transaction ID from the SMS'),
          ),
        ],
      ]);
}

class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String currency;
  final ValueChanged<String>? onChanged;
  const MoneyField({super.key, required this.controller, required this.label, required this.currency, this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: '$label ($currency)'),
      );
}

const gap = SizedBox(height: 12);

class FormDialog extends StatefulWidget {
  final String title;
  final List<Widget> Function(BuildContext context, void Function(void Function()) setState) fields;
  final String confirm;
  final Future<void> Function(BuildContext context) onConfirm;
  const FormDialog({super.key, required this.title, required this.fields, required this.confirm, required this.onConfirm});
  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
        // Own messenger: a refusal like "cash does not match" shows above the dialog, not dimmed behind it.
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Builder(
            builder: (inner) => AlertDialog(
              title: Text(widget.title),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final f in widget.fields(inner, setState)) Padding(padding: const EdgeInsets.only(bottom: 12), child: f)],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: busy ? null : () => Navigator.pop(inner), child: const Text('Cancel')),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await widget.onConfirm(inner);
                          if (mounted) setState(() => busy = false);
                        },
                  child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.confirm),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Asks one line of text, like the reason for a rejection.
Future<String?> askText(BuildContext context, {required String title, required String label, String confirm = 'OK'}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        maxLines: 2,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(confirm)),
      ],
    ),
  );
}

String money(BuildContext c, int v) => Money.format(v, StateScope.of(c).currency);
