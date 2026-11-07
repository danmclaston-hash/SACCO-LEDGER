import 'package:flutter/material.dart';

import '../core/json.dart';
import '../core/money.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Lets any screen reach the app state.
class StateScope extends InheritedNotifier<AppState> {
  const StateScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<StateScope>()!.notifier!;
}

const channelNames = {'mtn_momo': 'MTN MoMo', 'airtel_money': 'Airtel Money', 'bank': 'Bank', 'cash': 'Cash'};
const purposeNames = {
  'shares': 'Buy shares',
  'savings': 'Savings deposit',
  'fine': 'Fine',
  'loan_repayment': 'Loan repayment',
  'emergency_contribution': 'Emergency contribution',
  'withdrawal': 'Savings withdrawal',
  'expense': 'Group expense',
};
const roleNames = {
  'org_admin': 'Organization Admin',
  'treasurer': 'Treasurer',
  'secretary': 'Secretary',
  'loan_officer': 'Loan Officer',
  'auditor': 'Auditor',
  'member': 'Member',
  'platform_admin': 'Platform Admin',
};
const editionNames = {'tier_1_vsla': 'Tier 1: Community Groups', 'tier_2_sacco': 'Tier 2: Digital SACCO', 'tier_3_intelligent': 'Tier 3: Intelligent Finance'};
const editionHints = {
  'tier_1_vsla': 'VSLA meetings, attendance, quorum, shares, fines, emergency fund, cycle share-out',
  'tier_2_sacco': 'Individual accounts, deposits, withdrawals, loan products, repayment schedules',
  'tier_3_intelligent': 'Full SACCO plus portfolio risk dashboards and risk flags',
};

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
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (trailing != null) trailing!,
        ],
      );
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
      'pending' || 'pending_approval' => (warnOrange, Colors.white),
      'rejected' || 'reversed' => (cs.error, cs.onError),
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
              child: Text('${m.s('full_name')} (${roleNames[m.s('role')] ?? m.s('role')})', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      );
}

class ChannelPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const ChannelPicker({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'How the money moved'),
        items: [for (final e in channelNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => onChanged(v ?? value),
      );
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
