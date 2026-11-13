import 'package:flutter/material.dart' hide Text, InputDecoration;
import 'package:flutter/services.dart';

import '../../core/catalog.dart';
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/pages.dart';
import '../../data/api.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'circles_screen.dart';
import '../text.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = StateScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AppPageView(
      children: [
        SectionTitle(
          '${st.t(AppPage.members.title)} (${st.members.length})',
          trailing: st.role.canManageMembers
              ? Wrap(spacing: 8, children: [
                  if (!st.org!.b('is_demo'))
                    OutlinedButton.icon(
                      onPressed: () => showInviteDialog(context, orgId: st.orgId),
                      icon: const Icon(Icons.mail_outline_rounded, size: 16),
                      label: const Text('Invite by email'),
                    ),
                  FilledButton.icon(onPressed: () => _form(context, st), icon: const Icon(Icons.person_add, size: 16), label: const Text('Add')),
                ])
              : null,
        ),
        if (st.role.canManageMembers && !st.org!.b('is_demo')) const CircleInvitesCard(),
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
                  '${Role.labelOf(m.s('role'))} • ${Money.maskPhone(m.n('phone'))} • NIN ${Money.maskNationalId(m.n('national_id'))}',
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
                        tooltip: tr('Copy code'),
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
                    if (st.role.canManageMembers) ...[
                      TextButton(onPressed: () => _form(context, st, m: m), child: const Text('Edit')),
                      if (m.s('id') != st.myMemberId) // nobody resets their own password here
                        TextButton(
                          onPressed: () => _newCode(context, st, m),
                          child: Text(m.b('has_account') ? 'Password reset' : 'Joining code'),
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

  /// Not yet in the app: a joining code. Already in the app: a password reset, which two different officers must agree to.
  Future<void> _newCode(BuildContext context, AppState st, Json m) async {
    try {
      final code = await st.api.newMemberCode(m.s('id'));
      await st.refresh();
      if (!context.mounted) return;
      if (code == null) {
        showMsg(
            context, 'Asked. A second officer (admin, secretary or treasurer) must open Members and tap "Password reset" for ${m.s('full_name')} to agree.');
      } else if (m.b('has_account')) {
        showMsg(context, 'Agreed. The reset code shows under ${m.s('full_name')}. Give it to them privately. It works for one day.');
      } else {
        showMsg(context, 'Joining code made. Give it to ${m.s('full_name')} privately.');
      }
    } on ApiError catch (e) {
      if (context.mounted) showMsg(context, e.message, error: true);
    }
  }

  /// The same questions for a new member and for editing one.
  void _form(BuildContext context, AppState st, {Json? m}) {
    final name = TextEditingController(text: m?.s('full_name'));
    final phone = TextEditingController(text: m?.s('phone'));
    final nin = TextEditingController(text: m?.s('national_id'));
    final kin = TextEditingController();
    final kinPhone = TextEditingController();
    var role = Role.parse(m?.s('role'));
    var active = m?.b('is_active') ?? true;
    showDialog(
      context: context,
      builder: (_) => FormDialog(
        title: m == null ? 'Add Member' : 'Edit ${m.s('full_name')}',
        confirm: m == null ? 'Add' : 'Save',
        fields: (ctx, set) => [
          TextField(controller: name, decoration: InputDecoration(labelText: 'Full name')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone')),
          TextField(controller: nin, decoration: InputDecoration(labelText: m == null ? 'National ID (NIN), optional' : 'National ID (NIN)')),
          if (st.role.isOrgAdmin)
            DropdownButtonFormField<Role>(
              initialValue: role,
              decoration: InputDecoration(labelText: 'Role'),
              items: [for (final r in Role.assignable) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (v) => set(() => role = v ?? role),
            ),
          if (m == null) ...[
            TextField(controller: kin, decoration: InputDecoration(labelText: 'Next of kin, optional')),
            TextField(controller: kinPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Next of kin phone, optional')),
          ] else
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => set(() => active = v)),
        ],
        onConfirm: (ctx) => m == null
            ? runAndClose(
                ctx,
                () => st.api.addMember(st.orgId,
                    name: name.text,
                    phone: Phones.normalize(phone.text, dial: st.dial),
                    nationalId: nin.text,
                    role: role.code,
                    kinName: kin.text,
                    kinPhone: Phones.normalize(kinPhone.text, dial: st.dial)),
                done: 'Member added. Their invite code is on their card.')
            : runAndClose(
                ctx,
                () => st.api.updateMember(m.s('id'), {
                      'full_name': name.text,
                      'phone': Phones.normalize(phone.text, dial: st.dial) ?? '',
                      'national_id': nin.text,
                      'role': role.code,
                      'is_active': active,
                    }),
                done: 'Saved.'),
      ),
    );
  }
}
