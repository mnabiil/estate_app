import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

Color billColor(BillStatus s) =>
    s == BillStatus.lunas ? Colors.green.shade600 : Colors.orange.shade700;

Color complaintColor(ComplaintStatus s) => switch (s) {
      ComplaintStatus.baru => Colors.blue.shade600,
      ComplaintStatus.diproses => Colors.orange.shade700,
      ComplaintStatus.selesai => Colors.green.shade600,
    };

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

class FilterBar<T> extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// Nilai `null` berarti "Semua".
  final Map<T?, String> options;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onChanged(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Menjalankan aksi async: tampilkan [success] bila berhasil, atau pesan error
/// bila gagal. Mengembalikan hasil aksi, atau `null` bila gagal.
Future<T?> runAction<T>(BuildContext context, Future<T> action,
    {String? success}) async {
  try {
    final result = await action;
    if (success != null && context.mounted) showSnack(context, success);
    return result;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    return null;
  }
}

/// Pengelola: pemberitahuan pendaftaran warga yang menunggu di perumahan
/// lain yang dikelola, dengan tombol untuk pindah ke perumahan itu.
class OtherEstatePendingBanner extends StatelessWidget {
  const OtherEstatePendingBanner({
    super.key,
    this.onSwitched,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  /// Dipanggil setelah berpindah perumahan (mis. untuk membuka daftar
  /// pendaftaran).
  final VoidCallback? onSwitched;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final items = store.pendingInOtherEstates;
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final (estate, count) in items)
          Card(
            margin: margin,
            color: scheme.tertiaryContainer,
            child: ListTile(
              leading: Icon(Icons.how_to_reg_outlined,
                  color: scheme.onTertiaryContainer),
              title: Text(
                '$count pendaftaran menunggu di ${estate.name}',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
              subtitle: Text('Ketuk untuk pindah ke perumahan ini',
                  style: TextStyle(color: scheme.onTertiaryContainer)),
              trailing: Icon(Icons.swap_horiz,
                  color: scheme.onTertiaryContainer),
              onTap: () async {
                final ok = await runAction(
                  context,
                  store.switchEstate(estate.id).then((_) => true),
                  success: 'Pindah ke ${estate.name}',
                );
                if (ok == true) onSwitched?.call();
              },
            ),
          ),
      ],
    );
  }
}

/// Pengelola: konfirmasi lalu reset password akun warga [name] (kepala
/// keluarga [residentId], atau anggota rumah [memberUid]) dan tampilkan
/// password sementara yang baru.
Future<void> resetResidentPasswordFlow(
  BuildContext context, {
  required String name,
  required String residentId,
  String? memberUid,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Reset password $name?'),
      content: const Text(
          'Password lama tidak berlaku lagi dan warga otomatis keluar dari '
          'semua HP. Anda akan mendapat password sementara baru untuk '
          'diberikan ke warga; warga wajib menggantinya saat login.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Reset password'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final result = await runAction(context,
      store.resetResidentPassword(residentId, memberUid: memberUid));
  if (result == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Password $name direset'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.email.isNotEmpty) Text('Email: ${result.email}'),
          const SizedBox(height: 8),
          const Text('Password sementara baru:'),
          SelectableText(result.tempPassword,
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 12),
          const Text('Catat sekarang: password ini tidak ditampilkan lagi. '
              'Berikan ke warga secara pribadi.'),
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

/// Pengelola: pilih perumahan aktif dari perumahan yang boleh dikelola akun
/// ini (`estateIds`). Semua menu (warga, tagihan, renovasi, dst.) mengikuti
/// perumahan yang dipilih.
Future<void> pickActiveEstate(BuildContext context) async {
  final pending = {
    for (final (e, n) in store.pendingInOtherEstates) e.id: n,
  };
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Pilih perumahan',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in store.estates)
                    ListTile(
                      leading: Icon(e.id == store.activeEstateId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(e.name),
                      subtitle: pending[e.id] != null
                          ? Text('${pending[e.id]} pendaftaran menunggu')
                          : null,
                      onTap: () => Navigator.pop(ctx, e.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (id == null || id == store.activeEstateId || !context.mounted) return;
  final name = store.estateNameOf(id);
  await runAction(context, store.switchEstate(id),
      success: 'Sekarang mengelola $name');
}
