import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'registrations_screen.dart';

/// Anggota rumah (keluarga / penyewa) yang punya akun sendiri dan berbagi
/// data rumah yang sama. Kepala keluarga & pengelola bisa menambah/menghapus.
class HouseholdScreen extends StatelessWidget {
  const HouseholdScreen({super.key, required this.residentId});

  final String residentId;

  Future<void> _add(BuildContext context) async {
    final input = await showDialog<_MemberInput>(
      context: context,
      builder: (_) => const _AddMemberDialog(),
    );
    if (input == null || !context.mounted) return;
    final confirmed = await confirmSave(context,
        title: 'Tambah anggota rumah?',
        details: {
          'Nama': input.name,
          'Hubungan': input.relation.label,
          'No. HP': input.phone,
          'Email': input.email,
          'Rumah': store.residentById(residentId)?.houseNo ?? '',
        });
    if (!confirmed || !context.mounted) return;
    String? tempPassword;
    var failed = false;
    try {
      tempPassword = await withProgress(
        context,
        store.addMember(
          residentId: residentId,
          name: input.name,
          relation: input.relation,
          phone: input.phone,
          email: input.email,
        ),
      );
    } catch (e) {
      failed = true;
      if (context.mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    }
    if (failed || !context.mounted) return;
    if (tempPassword == null) {
      showSnack(context, '${input.name} ditambahkan sebagai anggota rumah');
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
            const Text('Berikan secara pribadi. Password wajib diganti saat '
                'login pertama.'),
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

  Future<void> _remove(BuildContext context, HouseholdMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus akses ${m.name}?'),
        content: const Text('Akun login anggota ini dihapus dan tidak bisa '
            'lagi membuka data rumah.'),
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
    await runAction(context, store.removeMember(m.id),
        success: 'Akses ${m.name} dihapus');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final r = store.residentById(residentId);
        final members = store.membersOf(residentId);
        final canManage = store.canManageMembers(residentId);
        final me = store.currentUser;
        final full = members.length >= maxHouseholdMembers;

        return Scaffold(
          appBar: AppBar(title: const Text('Anggota Rumah')),
          floatingActionButton: canManage && !full
              ? FloatingActionButton.extended(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Tambah anggota'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(
                'Rumah ${r?.houseNo ?? '-'}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Semua anggota memakai akun masing-masing dan melihat data '
                'rumah yang sama: tagihan, keluhan, tamu, dan renovasi.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (r != null)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.lime,
                      foregroundColor: Colors.white,
                      child: Icon(Icons.star),
                    ),
                    title: Text(r.name),
                    subtitle: Text([
                      'Kepala keluarga',
                      if (r.phone.isNotEmpty) r.phone,
                    ].join(' · ')),
                    trailing: me?.isPrimary == true &&
                            me?.residentId == residentId
                        ? const Text('Anda')
                        : null,
                  ),
                ),
              if (canManage && store.joinRequestsFor(residentId).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Permintaan bergabung',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 4),
                for (final req in store.joinRequestsFor(residentId))
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.person_add_alt_1),
                      title: Text(req.name),
                      subtitle: Text(
                          '${req.relation?.label ?? 'Anggota'} · ${req.phone} '
                          '· mendaftar sendiri'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => RegistrationDetailScreen(
                                  registrationId: req.id))),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text('Anggota (${members.length}/$maxHouseholdMembers)',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              if (members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    canManage
                        ? 'Belum ada anggota. Tambahkan pasangan, anak, orang '
                            'tua, atau penyewa agar mereka bisa memakai aplikasi '
                            'dengan akun sendiri.'
                        : 'Belum ada anggota rumah.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final m in members)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                        child: Text(m.name.isEmpty ? '?' : m.name[0])),
                    title: Text(m.name),
                    subtitle: Text([
                      m.relation.label,
                      if (m.phone.isNotEmpty) m.phone,
                      if (m.email.isNotEmpty) m.email,
                    ].join(' · ')),
                    trailing: canManage
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (store.can(AdminPermission.residents) &&
                                  store.isFirebase)
                                IconButton(
                                  tooltip: 'Reset password',
                                  icon: const Icon(Icons.lock_reset),
                                  onPressed: () => resetResidentPasswordFlow(
                                    context,
                                    name: m.name,
                                    residentId: residentId,
                                    memberUid: m.id,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Hapus akses',
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: () => _remove(context, m),
                              ),
                            ],
                          )
                        : (me?.email != null && me?.email == m.email
                            ? const Text('Anda')
                            : null),
                  ),
                ),
              if (!canManage)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Hanya kepala keluarga atau pengelola yang dapat menambah '
                    'atau menghapus anggota.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (full && canManage)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                      'Batas $maxHouseholdMembers anggota tercapai.',
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

typedef _MemberInput = ({
  String name,
  MemberRelation relation,
  String phone,
  String email,
});

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  MemberRelation _relation = MemberRelation.pasangan;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emailRequired = store.isFirebase;
    return AlertDialog(
      title: const Text('Tambah anggota rumah'),
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
                decoration: const InputDecoration(labelText: 'Nama lengkap'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              Text('Hubungan', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in MemberRelation.values)
                    ChoiceChip(
                      label: Text(r.label),
                      selected: _relation == r,
                      onSelected: (_) => setState(() => _relation = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No. HP'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: emailRequired
                      ? 'Email (untuk login)'
                      : 'Email (opsional di mode demo)',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return emailRequired ? 'Wajib diisi' : null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                      ? null
                      : 'Email tidak valid';
                },
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
              Navigator.pop<_MemberInput>(context, (
                name: _name.text.trim(),
                relation: _relation,
                phone: _phone.text.trim(),
                email: _email.text.trim(),
              ));
            }
          },
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}
