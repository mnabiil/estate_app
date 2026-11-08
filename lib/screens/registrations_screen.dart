import 'package:flutter/material.dart';

import '../models.dart';
import '../photo_widgets.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';

/// Pengelola: verifikasi pendaftaran warga mandiri.
class RegistrationsScreen extends StatefulWidget {
  const RegistrationsScreen({super.key});

  @override
  State<RegistrationsScreen> createState() => _RegistrationsScreenState();
}

class _RegistrationsScreenState extends State<RegistrationsScreen> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = _history
            ? (store.registrations
                .where((r) => r.status != RegistrationStatus.menunggu)
                .toList()
              ..sort((a, b) => (b.reviewedAt ?? b.createdAt)
                  .compareTo(a.reviewedAt ?? a.createdAt)))
            : store.pendingRegistrations;
        return Scaffold(
          appBar: AppBar(title: const Text('Pendaftaran Warga')),
          body: Column(
            children: [
              FilterBar<bool>(
                options: {
                  false: 'Menunggu (${store.pendingRegistrations.length})',
                  true: 'Riwayat',
                },
                selected: _history,
                onChanged: (v) => setState(() => _history = v ?? false),
              ),
              const OtherEstatePendingBanner(),
              if (!store.registrationOpen)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Pendaftaran online ditutup'),
                    subtitle: const Text(
                        'Buka lewat Master Data → Profil perumahan.'),
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.how_to_reg_outlined,
                        message: _history
                            ? 'Belum ada riwayat pendaftaran.'
                            : 'Tidak ada pendaftaran yang menunggu.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: list.length,
                        itemBuilder: (context, i) => _RegistrationCard(list[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Color _statusColor(RegistrationStatus s) => switch (s) {
      RegistrationStatus.menunggu => Colors.blue.shade600,
      RegistrationStatus.disetujui => AppColors.limeDark,
      RegistrationStatus.ditolak => Colors.red.shade600,
    };

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard(this.r);

  final Registration r;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase())),
        title: Text(r.name),
        subtitle: Text([
          r.isJoin
              ? 'Gabung ke ${r.houseNo} · ${r.relation?.label ?? 'anggota'}'
              : 'Warga baru · Rumah ${r.houseNo}',
          if (r.clusterName.isNotEmpty) r.clusterName,
          formatDate(r.createdAt),
        ].join(' · ')),
        trailing: StatusChip(r.status.label, _statusColor(r.status)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RegistrationDetailScreen(registrationId: r.id))),
      ),
    );
  }
}

class RegistrationDetailScreen extends StatelessWidget {
  const RegistrationDetailScreen({super.key, required this.registrationId});

  final String registrationId;

  Future<void> _reject(BuildContext context, Registration r) async {
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak pendaftaran?'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: reason,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Alasan (dilihat pendaftar)',
              hintText: 'Contoh: nama tidak sesuai data pemilik rumah; '
                  'lampirkan kontrak sewa',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, store.rejectRegistration(r.id, reason.text.trim()),
        success: 'Pendaftaran ${r.name} ditolak');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final r = store.registrationById(registrationId);
        if (r == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.search_off, message: 'Pendaftaran tidak ditemukan'),
          );
        }
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final house = store.houseById(r.houseId);
        final occupant = house == null ? null : store.residentOfHouse(house.id);
        final pending = r.status == RegistrationStatus.menunggu;
        final type = house == null ? null : store.houseTypeOf(house);
        final canReview = store.canReviewRegistration(r);
        final household =
            r.isJoin ? store.residentById(r.residentId ?? '') : null;
        // Masalah yang menghalangi persetujuan.
        final String? blocker = r.isJoin
            ? (household == null && store.isAdmin
                ? 'Data rumah tujuan tidak ditemukan.'
                : store.membersOf(r.residentId ?? '').length >=
                        maxHouseholdMembers
                    ? 'Anggota rumah sudah penuh ($maxHouseholdMembers orang).'
                    : null)
            : house == null
                ? 'Rumah sudah tidak ada di master data.'
                : occupant != null
                    ? 'Rumah ini sudah ditempati ${occupant.name}.'
                    : null;

        Widget row(IconData icon, String label, String value) => ListTile(
              leading: Icon(icon),
              title: Text(value),
              subtitle: Text(label),
              dense: true,
            );

        return Scaffold(
          appBar: AppBar(title: const Text('Detail Pendaftaran')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.name, style: theme.textTheme.titleLarge),
                  ),
                  StatusChip(r.status.label, _statusColor(r.status)),
                ],
              ),
              Text('Didaftarkan ${formatDate(r.createdAt)}',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    row(Icons.home_outlined, 'Rumah yang diajukan', [
                      'Rumah ${r.houseNo}',
                      if (r.clusterName.isNotEmpty) r.clusterName,
                      if (type != null) type.name,
                    ].join(' · ')),
                    if (r.isJoin) ...[
                      row(Icons.family_restroom, 'Jenis pendaftaran',
                          'Gabung sebagai ${r.relation?.label ?? 'anggota'}'),
                      if (household != null)
                        row(Icons.star_outline, 'Kepala keluarga',
                            household.name),
                    ] else
                      row(Icons.badge_outlined, 'Status hunian',
                          'Warga baru · ${r.occupancy.label}'),
                    row(Icons.phone_outlined, 'No. HP', r.phone),
                    row(Icons.email_outlined, 'Email (akun login)', r.email),
                  ],
                ),
              ),
              if (pending && blocker != null)
                Card(
                  color: scheme.errorContainer,
                  child: ListTile(
                    leading: Icon(Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer),
                    title: Text(
                      blocker,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                    subtitle: Text('Tolak dan minta pendaftar memilih ulang.',
                        style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Dokumen pendukung', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (r.docUrl == null || r.docUrl!.isEmpty)
                Text('Tidak ada. Verifikasi bisa dilakukan langsung, mis. '
                    'menghubungi No. HP di atas.',
                    style: theme.textTheme.bodySmall)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: PhotoStrip(photos: [r.docUrl!], size: 120),
                ),
              if (r.note.isNotEmpty) ...[
                const SizedBox(height: 16),
                row(Icons.sticky_note_2_outlined, 'Alasan penolakan', r.note),
              ],
              if (pending && canReview) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: blocker != null
                      ? null
                      : () async {
                          final ok = await confirmSave(context,
                              title: r.isJoin
                                  ? 'Setujui sebagai anggota rumah?'
                                  : 'Setujui pendaftaran?',
                              details: {
                                'Nama': r.name,
                                'Rumah': r.houseNo,
                                'Email': r.email,
                                'No. HP': r.phone,
                              },
                              note: 'Setelah disetujui, akun bisa langsung '
                                  'dipakai.',
                              action: 'Ya, setujui');
                          if (!ok || !context.mounted) return;
                          final done = await runAction(
                            context,
                            store.approveRegistration(r.id).then((_) => true),
                            success: r.isJoin
                                ? '${r.name} kini anggota rumah ${r.houseNo}'
                                : '${r.name} kini terdaftar sebagai warga',
                          );
                          if (done == true && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.how_to_reg),
                  label: Text(r.isJoin
                      ? 'Setujui sebagai anggota rumah'
                      : 'Setujui & aktifkan akun'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => _reject(context, r),
                  icon: const Icon(Icons.close),
                  label: const Text('Tolak'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
