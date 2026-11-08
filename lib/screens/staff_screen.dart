import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Tim pengelola & level akses perumahan aktif. Hanya pemilik yang bisa
/// mengubah; anggota tim lain hanya melihat.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Tim Pengelola'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Tim'),
              Tab(text: 'Level akses'),
            ]),
          ),
          body: const TabBarView(children: [_TeamTab(), _RolesTab()]),
        ),
      ),
    );
  }
}

class _OwnerOnlyNote extends StatelessWidget {
  const _OwnerOnlyNote();

  @override
  Widget build(BuildContext context) {
    if (store.isOwner) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text('Level Anda: ${store.myStaff?.levelLabel ?? '-'}'),
        subtitle: const Text('Hanya pemilik yang bisa mengubah tim & level akses.'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tim
// ---------------------------------------------------------------------------

class _TeamTab extends StatelessWidget {
  const _TeamTab();

  Future<void> _add(BuildContext context) async {
    final input = await showDialog<_StaffInput>(
      context: context,
      builder: (_) => const _AddStaffDialog(),
    );
    if (input == null || !context.mounted) return;
    String? tempPassword;
    var failed = false;
    try {
      tempPassword = await store.addStaff(
        name: input.name,
        email: input.email,
        phone: input.phone,
        roleId: input.roleId,
      );
    } catch (e) {
      failed = true;
      if (context.mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    }
    if (failed || !context.mounted) return;
    if (tempPassword == null) {
      showSnack(context, '${input.name} ditambahkan ke tim');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Akun ${input.name} dibuat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${input.email}'),
            const SizedBox(height: 8),
            const Text('Password sementara:'),
            SelectableText(tempPassword!,
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            const Text('Berikan secara pribadi. Wajib diganti saat login '
                'pertama.'),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Selesai')),
        ],
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, StaffMember m) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Level akses ${m.name}',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Pemilik'),
              subtitle: const Text('Akses penuh, termasuk mengatur tim'),
              selected: m.isOwner,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final r in store.adminRoles)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(r.name),
                subtitle: Text(_permSummary(r.permissions)),
                selected: !m.isOwner && m.roleId == r.id,
                onTap: () => Navigator.pop(ctx, r.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await runAction(
        context, store.setStaffRole(m.id, picked.isEmpty ? null : picked),
        success: 'Level ${m.name} diperbarui');
  }

  Future<void> _remove(BuildContext context, StaffMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Keluarkan ${m.name}?'),
        content: const Text('Akses pengelola ke perumahan ini dicabut. Bila '
            'tidak mengelola perumahan lain, akun loginnya dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, store.removeStaff(m.id),
        success: '${m.name} dikeluarkan dari tim');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owner = store.isOwner;
    final list = store.staff.toList()
      ..sort((a, b) {
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final meListed = store.myStaff != null;
    return Scaffold(
      floatingActionButton: owner
          ? FloatingActionButton.extended(
              onPressed: () => _add(context),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Tambah anggota'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _OwnerOnlyNote(),
          if (!meListed && owner)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.lime,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.star),
                ),
                title: Text('${store.currentUser?.name ?? ''} (Anda)'),
                subtitle: const Text('Pemilik · akses penuh'),
              ),
            ),
          for (final m in list)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      m.isOwner ? AppColors.lime : theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: m.isOwner
                      ? const Icon(Icons.star)
                      : Text(m.name.isEmpty ? '?' : m.name[0]),
                ),
                title: Text(m.id == store.myStaff?.id ? '${m.name} (Anda)' : m.name),
                subtitle: Text([
                  m.levelLabel,
                  if (!m.isOwner) _permSummary(m.permissions),
                  if (m.email.isNotEmpty) m.email,
                ].join(' · ')),
                isThreeLine: !m.isOwner,
                trailing: owner && m.id != store.myStaff?.id
                    ? PopupMenuButton<String>(
                        onSelected: (v) => v == 'role'
                            ? _changeRole(context, m)
                            : _remove(context, m),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'role', child: Text('Ganti level')),
                          PopupMenuItem(value: 'remove', child: Text('Keluarkan')),
                        ],
                      )
                    : null,
              ),
            ),
          if (list.isEmpty && !owner)
            const EmptyState(icon: Icons.groups_outlined, message: 'Belum ada tim.'),
        ],
      ),
    );
  }
}

String _permSummary(Set<AdminPermission> perms) => perms.isEmpty
    ? 'Tanpa hak ubah'
    : [for (final p in AdminPermission.values) if (perms.contains(p)) p.label]
        .join(', ');

typedef _StaffInput = ({String name, String email, String phone, String? roleId});

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  late String _roleId = store.adminRoles.isEmpty ? '' : store.adminRoles.first.id;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah anggota tim'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (untuk login)'),
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch((v ?? '').trim())
                    ? null
                    : 'Email tidak valid',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No. HP (opsional)'),
              ),
              const SizedBox(height: 16),
              Text('Level akses', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in store.adminRoles)
                    ChoiceChip(
                      label: Text(r.name),
                      selected: _roleId == r.id,
                      onSelected: (_) => setState(() => _roleId = r.id),
                    ),
                  ChoiceChip(
                    label: const Text('Pemilik (akses penuh)'),
                    selected: _roleId.isEmpty,
                    onSelected: (_) => setState(() => _roleId = ''),
                  ),
                ],
              ),
              if (store.adminRoles.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Buat level akses dulu di tab "Level akses" '
                      'untuk memberi hak terbatas.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop<_StaffInput>(context, (
                name: _name.text.trim(),
                email: _email.text.trim(),
                phone: _phone.text.trim(),
                roleId: _roleId.isEmpty ? null : _roleId,
              ));
            }
          },
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Level akses
// ---------------------------------------------------------------------------

/// Contoh level siap pakai untuk mempercepat pengaturan.
const _templates = <(String, Set<AdminPermission>)>[
  ('Bendahara', {AdminPermission.billing}),
  (
    'Admin Warga',
    {
      AdminPermission.residents,
      AdminPermission.complaints,
      AdminPermission.announcements,
    }
  ),
  ('Satpam', {AdminPermission.visitors, AdminPermission.renovationLogs}),
  (
    'Koordinator Bangunan',
    {AdminPermission.renovations, AdminPermission.renovationLogs}
  ),
];

class _RolesTab extends StatelessWidget {
  const _RolesTab();

  Future<void> _edit(BuildContext context, [AdminRole? role]) async {
    final result = await showDialog<(String, Set<AdminPermission>)>(
      context: context,
      builder: (_) => _RoleDialog(role: role),
    );
    if (result == null || !context.mounted) return;
    await runAction(
      context,
      store.saveAdminRole(result.$1, result.$2, id: role?.id),
      success: role == null ? 'Level ${result.$1} dibuat' : 'Level disimpan',
    );
  }

  Future<void> _delete(BuildContext context, AdminRole r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus level ${r.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, store.deleteAdminRole(r.id), success: 'Dihapus');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owner = store.isOwner;
    final unusedTemplates = _templates
        .where((t) => !store.adminRoles
            .any((r) => r.name.toLowerCase() == t.$1.toLowerCase()))
        .toList();
    return Scaffold(
      floatingActionButton: owner
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text('Level baru'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _OwnerOnlyNote(),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Pemilik'),
              subtitle: const Text('Semua hak, termasuk mengatur tim & level '
                  'akses. Tidak bisa diubah.'),
            ),
          ),
          for (final r in store.adminRoles)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(r.name),
                subtitle: Text([
                  _permSummary(r.permissions),
                  '${store.staff.where((m) => !m.isOwner && m.roleId == r.id).length} anggota',
                ].join('\n')),
                isThreeLine: true,
                onTap: owner ? () => _edit(context, r) : null,
                trailing: owner
                    ? IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(context, r),
                      )
                    : null,
              ),
            ),
          if (owner && unusedTemplates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Tambah cepat dari contoh',
                  style: theme.textTheme.labelLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, perms) in unusedTemplates)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(name),
                      onPressed: () => runAction(
                          context, store.saveAdminRole(name, perms),
                          success: 'Level $name dibuat'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleDialog extends StatefulWidget {
  const _RoleDialog({this.role});

  final AdminRole? role;

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.role?.name);
  late final Set<AdminPermission> _perms = {...?widget.role?.permissions};
  bool _showError = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.role == null ? 'Level akses baru' : 'Ubah level akses'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _name,
                autofocus: widget.role == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama level',
                  hintText: 'Contoh: Bendahara',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 8),
              for (final p in AdminPermission.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _perms.contains(p),
                  title: Text(p.label),
                  subtitle: Text(p.description),
                  onChanged: (v) => setState(() {
                    v == true ? _perms.add(p) : _perms.remove(p);
                    _showError = false;
                  }),
                ),
              if (_showError)
                Text('Pilih minimal satu hak akses',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              Text(
                'Semua pengelola tetap bisa melihat data perumahan. Hak di atas '
                'menentukan apa yang boleh diubah.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            final ok = _formKey.currentState!.validate();
            setState(() => _showError = _perms.isEmpty);
            if (ok && _perms.isNotEmpty) {
              Navigator.pop(context, (_name.text.trim(), Set.of(_perms)));
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
