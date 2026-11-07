import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/search_index.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  static const roles = ['member', 'org_admin', 'treasurer', 'secretary', 'loan_officer', 'auditor'];

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AppPageView(
      children: [
        SectionTitle(
          '${st.t('members')} (${st.members.length})',
          trailing: st.canManageMembers
              ? FilledButton.icon(onPressed: () => _add(context, st), icon: const Icon(Icons.person_add, size: 16), label: const Text('Add'))
              : null,
        ),
        if (st.members.isEmpty) const EmptyNote('No members yet.'),
        for (final m in st.members)
          SaccoCard(
            radius: 12,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'M${m.i('member_no')} • ${m.s('full_name')}',
                        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: m.b('is_active') ? null : cs.outline),
                      ),
                    ),
                    Text(
                      money(context, m.i('savings')),
                      style: tt.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                    ),
                  ],
                ),
                Text(
                  '${roleNames[m.s('role')]} • ${Money.maskPhone(m.n('phone'))} • NIN ${Money.maskNationalId(m.n('national_id'))}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '${m.b('has_account') ? 'Linked to the app' : 'Not linked yet'}${m.b('is_active') ? '' : ' • Inactive'}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (m.n('invite_code') != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Code: ${m.s('invite_code')}',
                          style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: m.s('invite_code')));
                          showMsg(context, 'Code copied. Give it to ${m.s('full_name')} privately.');
                        },
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => st.goTo(AppPage.statements, memberId: m.s('id')),
                      child: const Text('Statement'),
                    ),
                    if (st.canManageMembers) ...[
                      TextButton(onPressed: () => _edit(context, st, m), child: const Text('Edit')),
                      TextButton(
                        onPressed: () async {
                          final err = await st.act(() async {
                            await st.api.newMemberCode(m.s('id'));
                          });
                          if (context.mounted) showMsg(context, err ?? 'New code made. It works for joining or for a forgotten password.', error: err != null);
                        },
                        child: const Text('New code'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _add(BuildContext context, AppState st) {
    final name = TextEditingController();
    final phone = TextEditingController();
    final nin = TextEditingController();
    final kin = TextEditingController();
    final kinPhone = TextEditingController();
    var role = 'member';
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Add Member',
        confirm: 'Add',
        fields: (ctx, set) => [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          TextField(
            controller: nin,
            decoration: const InputDecoration(labelText: 'National ID (NIN), optional'),
          ),
          if (st.isOrgAdmin)
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(roleNames[r]!))],
              onChanged: (v) => set(() => role = v ?? role),
            ),
          TextField(
            controller: kin,
            decoration: const InputDecoration(labelText: 'Next of kin, optional'),
          ),
          TextField(
            controller: kinPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Next of kin phone, optional'),
          ),
        ],
        onConfirm: (ctx) => runAndClose(ctx, st, () async {
          await st.api.addMember(st.orgId, name: name.text, phone: phone.text, nationalId: nin.text, role: role, kinName: kin.text, kinPhone: kinPhone.text);
        }, done: 'Member added. Their invite code is on their card.'),
      ),
    );
  }

  void _edit(BuildContext context, AppState st, Json m) {
    final name = TextEditingController(text: m.s('full_name'));
    final phone = TextEditingController(text: m.s('phone'));
    final nin = TextEditingController(text: m.s('national_id'));
    var role = m.s('role');
    var active = m.b('is_active');
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: 'Edit ${m.s('full_name')}',
        confirm: 'Save',
        fields: (ctx, set) => [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          TextField(
            controller: nin,
            decoration: const InputDecoration(labelText: 'National ID (NIN)'),
          ),
          if (st.isOrgAdmin)
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(roleNames[r]!))],
              onChanged: (v) => set(() => role = v ?? role),
            ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => set(() => active = v)),
        ],
        onConfirm: (ctx) => runAndClose(
          ctx,
          st,
          () => st.api.updateMember(m.s('id'), {'full_name': name.text, 'phone': phone.text, 'national_id': nin.text, 'role': role, 'is_active': active}),
          done: 'Saved.',
        ),
      ),
    );
  }
}
