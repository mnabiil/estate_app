import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../photo_widgets.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';

/// Warna & label status gabungan (status + tahap pekerjaan).
(String, Color) renovationBadge(Renovation r) {
  switch (r.status) {
    case RenovationStatus.diajukan:
      return ('Menunggu persetujuan', Colors.blue.shade600);
    case RenovationStatus.disetujui when r.awaitingDeposit:
      return r.depositStatus == DepositStatus.menungguVerifikasi
          ? ('Verifikasi deposit', Colors.blue.shade600)
          : ('Disetujui · bayar deposit', Colors.orange.shade700);
    case RenovationStatus.disetujui:
      return switch (r.phaseOn(DateTime.now())) {
        RenovationPhase.belumMulai => ('Belum mulai', Colors.blue.shade600),
        RenovationPhase.berjalan => ('Berjalan', AppColors.limeDark),
        RenovationPhase.terlambat => ('Lewat batas waktu', Colors.red.shade600),
      };
    case RenovationStatus.ditolak:
      return ('Ditolak', Colors.red.shade600);
    case RenovationStatus.selesai:
      return ('Selesai', Colors.grey.shade600);
    case RenovationStatus.dibatalkan:
      return ('Dibatalkan', Colors.grey.shade600);
  }
}

String _period(Renovation r) =>
    '${formatDate(r.startDate)} – ${formatDate(r.endDate)} (${r.durationDays} hari)';

// ---------------------------------------------------------------------------
// Daftar
// ---------------------------------------------------------------------------

class RenovationsScreen extends StatefulWidget {
  const RenovationsScreen({super.key});

  @override
  State<RenovationsScreen> createState() => _RenovationsScreenState();
}

enum _Filter { aktif, selesai, semua }

class _RenovationsScreenState extends State<RenovationsScreen> {
  /// Pengelola mengatur nominal deposit renovasi kecil (ringan) & besar (berat).
  Future<void> _editDeposits() async {
    final small = TextEditingController(text: '${store.depositSmall}');
    final large = TextEditingController(text: '${store.depositLarge}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nominal deposit renovasi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Berlaku untuk pengajuan baru di $estateName.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: small,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Renovasi kecil / ringan', prefixText: 'Rp '),
            ),
            TextField(
              controller: large,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Renovasi besar / berat', prefixText: 'Rp '),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    int parse(TextEditingController c) =>
        int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final confirmed = await confirmSave(context,
        title: 'Simpan nominal deposit?',
        details: {
          'Perumahan': estateName,
          'Renovasi kecil': formatRupiah(parse(small)),
          'Renovasi besar': formatRupiah(parse(large)),
        },
        note: 'Berlaku untuk pengajuan baru.');
    if (!confirmed || !mounted) return;
    await runAction(
        context, store.setRenovationDeposits(parse(small), parse(large)),
        success: 'Nominal deposit disimpan');
  }

  _Filter _filter = _Filter.aktif;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final isAdmin = store.isAdmin;
        final rid = store.currentUser?.residentId;
        var list = store.renovations
            .where((r) => isAdmin || r.residentId == rid)
            .toList();
        list = switch (_filter) {
          _Filter.aktif => list.where((r) => r.isActive).toList(),
          _Filter.selesai => list.where((r) => !r.isActive).toList(),
          _Filter.semua => list,
        };
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final hasActive = store.renovations
            .any((r) => r.residentId == rid && r.isActive);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Ijin Renovasi'),
            actions: [
              if (store.can(AdminPermission.renovations) ||
                  store.can(AdminPermission.masterData))
                IconButton(
                  tooltip: 'Atur nominal deposit',
                  icon: const Icon(Icons.tune),
                  onPressed: _editDeposits,
                ),
            ],
          ),
          floatingActionButton: isAdmin || hasActive
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const RenovationFormScreen())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajukan renovasi'),
                ),
          body: Column(
            children: [
              if (isAdmin) const SyncProblemsCard(),
              FilterBar<_Filter>(
                options: const {
                  _Filter.aktif: 'Aktif',
                  _Filter.selesai: 'Riwayat',
                  _Filter.semua: 'Semua',
                },
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v ?? _Filter.semua),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.construction,
                        message: isAdmin
                            ? 'Tidak ada ijin renovasi.'
                            : 'Belum ada ijin renovasi.\n'
                                'Ajukan sebelum memulai pekerjaan renovasi.',
                      )
                    : RefreshIndicator(
                        onRefresh: store.refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: list.length,
                          itemBuilder: (context, i) =>
                              _RenovationCard(list[i], showResident: isAdmin),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RenovationCard extends StatelessWidget {
  const _RenovationCard(this.r, {required this.showResident});

  final Renovation r;
  final bool showResident;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = store.residentById(r.residentId);
    final (label, color) = renovationBadge(r);
    final logs = store.logsOf(r.id).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RenovationDetailScreen(renovationId: r.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    r.type == RenovationType.besar
                        ? Icons.domain
                        : Icons.format_paint_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.type.label,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  StatusChip(label, color),
                ],
              ),
              if (showResident) ...[
                const SizedBox(height: 6),
                Text('${res?.name ?? '-'} · Rumah ${res?.houseNo ?? '-'}',
                    style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 4),
              Text(r.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(_period(r), style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.savings_outlined,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    'Deposit ${formatRupiah(r.deposit)} · ${r.depositStatus.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (logs > 0)
                    Text('$logs catatan barang',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form pengajuan (warga)
// ---------------------------------------------------------------------------

class RenovationFormScreen extends StatefulWidget {
  const RenovationFormScreen({super.key});

  @override
  State<RenovationFormScreen> createState() => _RenovationFormScreenState();
}

class _RenovationFormScreenState extends State<RenovationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _contractor = TextEditingController();
  final _phone = TextEditingController();
  RenovationType _type = RenovationType.kecil;
  DateTimeRange? _range;
  final List<(XFile, int)> _files = [];
  bool _saving = false;
  bool _agree = false;

  Future<void> _addFiles() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedAttachmentExtensions,
      );
      for (final f in picked) {
        if (_files.length >= maxRenovationAttachments) {
          if (mounted) {
            showSnack(context, 'Maksimal $maxRenovationAttachments lampiran.');
          }
          break;
        }
        final size = await f.length() ?? 0;
        if (size > maxAttachmentBytes) {
          if (mounted) {
            showSnack(context,
                '${f.name} lebih dari ${formatFileSize(maxAttachmentBytes)}.');
          }
          continue;
        }
        if (mounted) setState(() => _files.add((f.xFile, size)));
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal memilih file: ${describeError(e)}');
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _contractor.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _range,
      helpText: 'Jangka waktu pekerjaan',
      saveText: 'Pilih',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    if (!valid || _range == null || !_agree) {
      if (_range == null) showSnack(context, 'Pilih jangka waktu pekerjaan.');
      if (_range != null && !_agree) {
        showSnack(context, 'Setujui ketentuan ijin renovasi terlebih dahulu.');
      }
      return;
    }
    final confirmed = await confirmSave(context,
        title: 'Ajukan ijin renovasi?',
        details: {
          'Jenis': _type.label,
          'Detail': _desc.text,
          'Kontraktor': _contractor.text,
          'No. HP': _phone.text,
          'Jangka waktu':
              '${formatDate(_range!.start)} – ${formatDate(_range!.end)}',
          'Deposit': formatRupiah(store.depositFor(_type)),
          'Lampiran': _files.isEmpty ? 'Tidak ada' : '${_files.length} file',
        },
        note: 'Deposit dibayar setelah pengajuan disetujui pengelola.',
        action: 'Ya, ajukan');
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      store.submitRenovation(
        type: _type,
        description: _desc.text.trim(),
        contractor: _contractor.text.trim(),
        contractorPhone: _phone.text.trim(),
        start: _range!.start,
        end: _range!.end,
        attachments: [for (final (f, _) in _files) f],
      ).then((_) => true),
      success: 'Ijin renovasi diajukan. Tunggu persetujuan pengelola.',
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajukan Ijin Renovasi')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Jenis renovasi', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final t in RenovationType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TypeOption(
                  type: t,
                  deposit: store.depositFor(t),
                  selected: _type == t,
                  onTap: () => setState(() => _type = t),
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Detail renovasi',
                hintText: 'Jelaskan bagian yang direnovasi, material utama, '
                    'perkiraan jumlah pekerja, dan jam kerja.\n'
                    'Contoh: ganti keramik dapur 12 m², cat ulang ruang tamu; '
                    '3 pekerja, 08.00–17.00',
                hintMaxLines: 4,
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 20)
                  ? 'Jelaskan lebih detail (min. 20 karakter)'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contractor,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Kontraktor / mandor',
                prefixIcon: Icon(Icons.engineering_outlined),
              ),
              validator: _required,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: 'No. HP kontraktor (opsional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(radiusField),
              onTap: _pickRange,
              child: InputDecorator(
                isEmpty: _range == null,
                decoration: const InputDecoration(
                  labelText: 'Jangka waktu pekerjaan',
                  prefixIcon: Icon(Icons.date_range),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text(_range == null
                    ? ''
                    : '${formatDate(_range!.start)} – ${formatDate(_range!.end)} '
                        '(${_range!.end.difference(_range!.start).inDays + 1} hari)'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                      'Lampiran (opsional, maks. $maxRenovationAttachments)',
                      style: theme.textTheme.labelLarge),
                ),
                TextButton.icon(
                  onPressed: _saving ||
                          _files.length >= maxRenovationAttachments
                      ? null
                      : _addFiles,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Tambah file'),
                ),
              ],
            ),
            Text(
              'Gambar desain, denah, RAB, atau foto kondisi saat ini. '
              'PDF, gambar, Word, atau Excel; maks. '
              '${formatFileSize(maxAttachmentBytes)} per file.',
              style: theme.textTheme.bodySmall,
            ),
            for (var i = 0; i < _files.length; i++)
              Card(
                child: ListTile(
                  leading: Icon(_fileIcon(_files[i].$1.name)),
                  title: Text(_files[i].$1.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatFileSize(_files[i].$2)),
                  trailing: IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.close),
                    onPressed:
                        _saving ? null : () => setState(() => _files.removeAt(i)),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(radiusCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deposit ${formatRupiah(store.depositFor(_type))}',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSecondaryContainer)),
                  const SizedBox(height: 4),
                  Text(
                    'Pengajuan ditinjau pengelola terlebih dahulu. Setelah '
                    'disetujui, bayar deposit lalu unggah bukti pembayaran; '
                    'pekerjaan boleh dimulai setelah deposit diverifikasi. '
                    'Deposit dikembalikan setelah renovasi selesai, dan dapat '
                    'dipotong bila ada kerusakan fasilitas umum, sisa '
                    'material/puing, atau pelanggaran tata tertib.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agree,
                    onChanged: (v) => setState(() => _agree = v ?? false),
                    title: const Text('Saya setuju dengan ketentuan di atas'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_saving ? 'Mengirim...' : 'Ajukan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.type,
    required this.deposit,
    required this.selected,
    required this.onTap,
  });

  final RenovationType type;
  final int deposit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.lime : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? scheme.onPrimary : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimary.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deposit ${formatRupiah(deposit)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.lime : scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail
// ---------------------------------------------------------------------------

class RenovationDetailScreen extends StatelessWidget {
  const RenovationDetailScreen({super.key, required this.renovationId});

  final String renovationId;

  Future<void> _approve(BuildContext context, Renovation r) async {
    final note = await _promptNote(context,
        title: 'Setujui ijin renovasi?',
        label: 'Catatan untuk warga (opsional)',
        hint: 'Contoh: jam kerja 08.00–17.00, Minggu libur',
        confirm: 'Setujui');
    if (note == null || !context.mounted) return;
    await runAction(context, store.approveRenovation(r.id, note: note),
        success: 'Ijin renovasi disetujui');
  }

  Future<void> _reject(BuildContext context, Renovation r) async {
    final reason = await _promptNote(context,
        title: 'Tolak ijin renovasi?',
        label: 'Alasan penolakan',
        required: true,
        confirm: 'Tolak',
        destructive: true);
    if (reason == null || !context.mounted) return;
    await runAction(context, store.rejectRenovation(r.id, reason),
        success: 'Ijin renovasi ditolak');
  }

  Future<void> _extend(BuildContext context, Renovation r) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: r.endDate.add(const Duration(days: 7)),
      firstDate: r.endDate.add(const Duration(days: 1)),
      lastDate: r.endDate.add(const Duration(days: 365)),
      helpText: 'Batas waktu baru',
    );
    if (picked == null || !context.mounted) return;
    final ok = await confirmSave(context,
        title: 'Perpanjang ijin renovasi?',
        details: {
          'Rumah': store.residentById(r.residentId)?.houseNo ?? '',
          'Batas lama': formatDate(r.endDate),
          'Batas baru': formatDate(picked),
        });
    if (!ok || !context.mounted) return;
    await runAction(context, store.extendRenovation(r.id, picked),
        success: 'Diperpanjang sampai ${formatDate(picked)}');
  }

  /// Verifikasi deposit transfer / catat deposit tunai diterima.
  Future<void> _markPaid(BuildContext context, Renovation r,
      {required bool cash}) async {
    final ok = await confirmSave(context,
        title: cash ? 'Terima deposit tunai?' : 'Verifikasi deposit?',
        details: {
          'Rumah': store.residentById(r.residentId)?.houseNo ?? '',
          'Deposit': formatRupiah(r.deposit),
          'Metode': cash ? 'Tunai' : (r.depositMethod ?? 'Transfer'),
        },
        note: cash
            ? 'Pastikan uang tunai sudah diterima.'
            : 'Pastikan dana sudah masuk ke rekening perumahan.',
        action: cash ? 'Ya, diterima' : 'Ya, verifikasi');
    if (!ok || !context.mounted) return;
    await runAction(context, store.markDepositPaid(r.id),
        success: cash
            ? 'Deposit tunai dicatat diterima'
            : 'Deposit terverifikasi. Pekerjaan boleh dimulai.');
  }

  Future<void> _complete(BuildContext context, Renovation r) async {
    final note = await _promptNote(context,
        title: 'Tandai renovasi selesai?',
        label: 'Hasil pemeriksaan (opsional)',
        hint: 'Contoh: lingkungan bersih, tidak ada kerusakan',
        confirm: 'Selesai');
    if (note == null || !context.mounted) return;
    await runAction(context, store.completeRenovation(r.id, note: note),
        success: 'Renovasi ditandai selesai');
  }

  Future<void> _refund(BuildContext context, Renovation r) async {
    final amount = TextEditingController(text: '${r.deposit}');
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kembalikan deposit'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Jumlah dikembalikan',
                  prefixText: 'Rp ',
                  helperText: 'Deposit ${formatRupiah(r.deposit)}',
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').replaceAll('.', ''));
                  if (n == null || n < 0 || n > r.deposit) {
                    return 'Isi 0 – ${formatRupiah(r.deposit)}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Alasan potongan (bila ada)',
                ),
                validator: (v) {
                  final n = int.tryParse(amount.text.replaceAll('.', ''));
                  if (n != null && n < r.deposit && (v ?? '').trim().isEmpty) {
                    return 'Wajib diisi bila deposit dipotong';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Kembalikan'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final n = int.parse(amount.text.replaceAll('.', ''));
    final confirmed = await confirmSave(context,
        title: 'Kembalikan deposit?',
        details: {
          'Rumah': store.residentById(r.residentId)?.houseNo ?? '',
          'Deposit': formatRupiah(r.deposit),
          'Dikembalikan': formatRupiah(n),
          if (n < r.deposit) 'Potongan': formatRupiah(r.deposit - n),
          'Alasan': note.text,
        },
        action: 'Ya, kembalikan');
    if (!confirmed || !context.mounted) return;
    await runAction(
      context,
      store.refundDeposit(r.id, n, note: note.text.trim()),
      success: 'Deposit ${formatRupiah(n)} dikembalikan',
    );
  }

  Future<void> _rejectProof(BuildContext context, Renovation r) async {
    final reason = await _promptNote(context,
        title: 'Tolak bukti pembayaran?',
        label: 'Alasan',
        hint: 'Contoh: nominal tidak sesuai, bukti tidak terbaca',
        required: true,
        confirm: 'Tolak',
        destructive: true);
    if (reason == null || !context.mounted) return;
    await runAction(context, store.rejectDepositProof(r.id, reason),
        success: 'Warga diminta mengirim ulang pembayaran');
  }

  Future<void> _confirmCancel(BuildContext context, Renovation r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan ijin renovasi?'),
        content: const Text('Pengajuan yang dibatalkan tidak bisa dilanjutkan. '
            'Ajukan ulang bila diperlukan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Batalkan ijin'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, store.cancelRenovation(r.id),
        success: 'Ijin renovasi dibatalkan');
  }

  Future<void> _payDeposit(BuildContext context, Renovation r) async {
    final result = await showDialog<(String, XFile?)>(
      context: context,
      builder: (_) => _PayDepositDialog(deposit: r.deposit),
    );
    if (result == null || !context.mounted) return;
    final (method, proof) = result;
    final ok = await confirmSave(context,
        title: 'Kirim pembayaran deposit?',
        details: {
          'Deposit': formatRupiah(r.deposit),
          'Metode': method,
          'Bukti': proof == null ? 'Tanpa foto' : 'Foto terlampir',
        },
        action: 'Ya, kirim');
    if (!ok || !context.mounted) return;
    await runAction(
      context,
      store.payDeposit(r.id, method: method, proof: proof),
      success: 'Pembayaran dikirim. Menunggu verifikasi pengelola.',
    );
  }

  Future<void> _addLog(BuildContext context, Renovation r) async {
    final result = await showDialog<_LogInput>(
      context: context,
      builder: (_) => const _LogDialog(),
    );
    if (result == null || !context.mounted) return;
    final ok = await confirmSave(context,
        title: 'Catat barang ${result.direction.label.toLowerCase()}?',
        details: {
          'Barang': result.item,
          'Jumlah': result.quantity,
          'Catatan': result.note,
          'Foto': result.photos.isEmpty
              ? 'Tanpa foto'
              : '${result.photos.length} foto',
        },
        action: 'Ya, catat');
    if (!ok || !context.mounted) return;
    await runAction(
      context,
      store.addRenovationLog(
        r.id,
        direction: result.direction,
        item: result.item,
        quantity: result.quantity,
        note: result.note,
        photos: result.photos,
      ),
      success: 'Barang ${result.direction.label.toLowerCase()} dicatat',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final r = store.renovationById(renovationId);
        if (r == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.search_off, message: 'Ijin tidak ditemukan'),
          );
        }
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final isAdmin = store.isAdmin;
        final res = store.residentById(r.residentId);
        final (label, color) = renovationBadge(r);
        final logs = store.logsOf(r.id);
        final canLog = r.canWork &&
            (store.currentUser?.residentId == r.residentId ||
                store.can(AdminPermission.renovationLogs) ||
                store.can(AdminPermission.renovations));
        final isOwner = store.currentUser?.residentId == r.residentId;

        return Scaffold(
          appBar: AppBar(title: Text(r.type.label)),
          floatingActionButton: canLog
              ? FloatingActionButton.extended(
                  onPressed: () => _addLog(context, r),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Catat barang'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Row(
                children: [
                  StatusChip(label, color),
                  const Spacer(),
                  Text('Diajukan ${formatDate(r.createdAt)}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 12),
              if (isAdmin)
                Text('${res?.name ?? '-'} · Rumah ${res?.houseNo ?? '-'}',
                    style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(r.description),
              const SizedBox(height: 12),
              _InfoRow(Icons.engineering_outlined, 'Kontraktor',
                  [r.contractor, if (r.contractorPhone.isNotEmpty) r.contractorPhone].join(' · ')),
              _InfoRow(Icons.event, 'Jangka waktu', _period(r)),
              if (r.canWork) _Progress(r),
              if (r.adminNote.isNotEmpty)
                _InfoRow(Icons.sticky_note_2_outlined, 'Catatan pengelola',
                    r.adminNote),
              if (r.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Lampiran (${r.attachments.length})',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final a in r.attachments) _AttachmentTile(a),
              ],
              const SizedBox(height: 12),
              _DepositCard(r),
              // ----- aksi -----
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (store.can(AdminPermission.renovations)) ...[
                    if (r.status == RenovationStatus.diajukan) ...[
                      FilledButton.icon(
                        onPressed: () => _approve(context, r),
                        icon: const Icon(Icons.check),
                        label: const Text('Setujui'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error),
                        onPressed: () => _reject(context, r),
                        icon: const Icon(Icons.close),
                        label: const Text('Tolak'),
                      ),
                    ],
                    if (r.status == RenovationStatus.disetujui &&
                        r.depositStatus == DepositStatus.menungguVerifikasi) ...[
                      FilledButton.icon(
                        onPressed: () => _markPaid(context, r, cash: false),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Verifikasi deposit'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error),
                        onPressed: () => _rejectProof(context, r),
                        icon: const Icon(Icons.close),
                        label: const Text('Tolak bukti'),
                      ),
                    ],
                    if (r.status == RenovationStatus.disetujui &&
                        r.depositStatus == DepositStatus.belumBayar)
                      OutlinedButton.icon(
                        onPressed: () => _markPaid(context, r, cash: true),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Terima deposit tunai'),
                      ),
                    if (r.canWork) ...[
                      OutlinedButton.icon(
                        onPressed: () => _extend(context, r),
                        icon: const Icon(Icons.more_time),
                        label: const Text('Perpanjang'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _complete(context, r),
                        icon: const Icon(Icons.task_alt),
                        label: const Text('Tandai selesai'),
                      ),
                    ],
                    if (r.depositStatus == DepositStatus.dibayar && !r.isActive)
                      FilledButton.icon(
                        onPressed: () => _refund(context, r),
                        icon: const Icon(Icons.undo),
                        label: const Text('Kembalikan deposit'),
                      ),
                  ],
                  if (!isAdmin &&
                      isOwner &&
                      r.status == RenovationStatus.disetujui &&
                      r.depositStatus == DepositStatus.belumBayar)
                    FilledButton.icon(
                      onPressed: () => _payDeposit(context, r),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Bayar deposit ${formatRupiah(r.deposit)}'),
                    ),
                  if ((store.can(AdminPermission.renovations) || isOwner) &&
                      (r.status == RenovationStatus.diajukan ||
                          (r.status == RenovationStatus.disetujui &&
                              r.depositStatus == DepositStatus.belumBayar)))
                    OutlinedButton.icon(
                      style:
                          OutlinedButton.styleFrom(foregroundColor: scheme.error),
                      onPressed: () => _confirmCancel(context, r),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(isAdmin ? 'Batalkan ijin' : 'Batalkan pengajuan'),
                    ),
                ],
              ),
              if (_nextStepHint(r, isAdmin) case final hint?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(hint, style: theme.textTheme.bodySmall),
                ),
              // ----- log barang -----
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Barang masuk & keluar',
                        style: theme.textTheme.titleMedium),
                  ),
                  if (logs.isNotEmpty)
                    Text(
                      '${logs.where((l) => l.direction == LogDirection.masuk).length} masuk · '
                      '${logs.where((l) => l.direction == LogDirection.keluar).length} keluar',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (logs.isEmpty)
                Text(
                  canLog
                      ? 'Belum ada catatan. Catat setiap barang/material yang '
                          'masuk atau keluar (puing, sisa material), '
                          'lengkap dengan fotonya.'
                      : 'Catatan barang dimulai setelah ijin disetujui dan '
                          'deposit diterima.',
                  style: theme.textTheme.bodySmall,
                ),
              for (var i = 0; i < logs.length; i++) ...[
                if (i == 0 || !isSameDay(logs[i].at, logs[i - 1].at))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(formatDate(logs[i].at),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                _LogTile(logs[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Progres jangka waktu: hari ke-x dari y, sisa hari, atau terlambat.
class _Progress extends StatelessWidget {
  const _Progress(this.r);

  final Renovation r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final phase = r.phaseOn(today);
    final total = r.durationDays;
    final day = today.difference(r.startDate).inDays + 1;
    final (text, value, color) = switch (phase) {
      RenovationPhase.belumMulai => (
          'Mulai dalam ${r.startDate.difference(today).inDays} hari',
          0.0,
          Colors.blue.shade600,
        ),
      RenovationPhase.berjalan => (
          'Hari ke-$day dari $total · sisa ${total - day} hari',
          day / total,
          AppColors.limeDark,
        ),
      RenovationPhase.terlambat => (
          'Lewat ${today.difference(r.endDate).inDays} hari dari batas waktu',
          1.0,
          Colors.red.shade600,
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DepositCard extends StatelessWidget {
  const _DepositCard(this.r);

  final Renovation r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refund = r.depositRefund ?? 0;
    final lines = <String>[
      if (r.status == RenovationStatus.diajukan)
        'Dibayar setelah ijin disetujui pengelola.',
      if (r.status == RenovationStatus.disetujui &&
          r.depositStatus == DepositStatus.belumBayar)
        'Ijin disetujui — silakan bayar deposit.',
      if (r.depositMethod != null) 'Metode: ${r.depositMethod}',
      if (r.depositSubmittedAt != null &&
          r.depositStatus == DepositStatus.menungguVerifikasi)
        'Dikirim ${formatDate(r.depositSubmittedAt!)}',
      if (r.depositPaidAt != null) 'Diterima ${formatDate(r.depositPaidAt!)}',
      if (r.depositStatus == DepositStatus.dikembalikan)
        'Dikembalikan ${formatRupiah(refund)}'
            '${r.depositRefundedAt != null ? ' pada ${formatDate(r.depositRefundedAt!)}' : ''}'
            '${refund < r.deposit ? ' (dipotong ${formatRupiah(r.deposit - refund)})' : ''}',
    ];
    final proof = r.depositProofUrl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: Text('Deposit ${formatRupiah(r.deposit)}'),
              subtitle: Text([r.depositStatus.label, ...lines].join('\n')),
              isThreeLine: lines.isNotEmpty,
              trailing: Icon(
                switch (r.depositStatus) {
                  DepositStatus.belumBayar => Icons.hourglass_empty,
                  DepositStatus.menungguVerifikasi => Icons.pending_outlined,
                  DepositStatus.dibayar => Icons.lock_outline,
                  DepositStatus.dikembalikan => Icons.check_circle_outline,
                },
                color: theme.colorScheme.primary,
              ),
            ),
            if (proof != null && proof.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    PhotoThumb(
                      source: proof,
                      size: 56,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PhotoViewer(photos: [proof]))),
                    ),
                    const SizedBox(width: 12),
                    Text('Bukti pembayaran', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lampiran pengajuan: gambar dibuka di aplikasi, file lain di aplikasi
/// lain (PDF viewer, dsb.).
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile(this.a);

  final RenovationAttachment a;

  Future<void> _open(BuildContext context) async {
    if (a.url.isEmpty) {
      showSnack(context, 'Lampiran contoh — tidak ada file untuk dibuka.');
      return;
    }
    if (a.isImage) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PhotoViewer(photos: [a.url])));
      return;
    }
    if (!a.url.startsWith('http')) {
      showSnack(context, 'Pratinjau dokumen tersedia di mode Firebase.');
      return;
    }
    final ok = await launchUrl(Uri.parse(a.url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showSnack(context, 'Tidak ada aplikasi untuk membuka ${a.name}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_fileIcon(a.name)),
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: a.size > 0 ? Text(formatFileSize(a.size)) : null,
        trailing: const Icon(Icons.open_in_new),
        onTap: () => _open(context),
      ),
    );
  }
}

IconData _fileIcon(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (n.endsWith('.doc') || n.endsWith('.docx')) return Icons.description_outlined;
  if (n.endsWith('.xls') || n.endsWith('.xlsx')) return Icons.table_chart_outlined;
  return Icons.image_outlined;
}

/// Langkah berikutnya, agar setiap pihak tahu apa yang harus dilakukan.
String? _nextStepHint(Renovation r, bool isAdmin) {
  if (r.status == RenovationStatus.diajukan) {
    return isAdmin
        ? 'Tinjau detail & lampiran, lalu setujui atau tolak.'
        : 'Menunggu tinjauan pengelola. Deposit dibayar setelah disetujui.';
  }
  if (r.status != RenovationStatus.disetujui) return null;
  return switch (r.depositStatus) {
    DepositStatus.belumBayar => isAdmin
        ? 'Menunggu warga membayar deposit. Pembayaran tunai bisa langsung '
            'dicatat.'
        : 'Bayar deposit lalu kirim bukti pembayarannya. Pekerjaan boleh '
            'dimulai setelah deposit diverifikasi.',
    DepositStatus.menungguVerifikasi => isAdmin
        ? 'Periksa bukti pembayaran, lalu verifikasi.'
        : 'Pembayaran sedang diverifikasi pengelola.',
    _ => null,
  };
}

class _PayDepositDialog extends StatefulWidget {
  const _PayDepositDialog({required this.deposit});

  final int deposit;

  @override
  State<_PayDepositDialog> createState() => _PayDepositDialogState();
}

class _PayDepositDialogState extends State<_PayDepositDialog> {
  static const _methods = ['Transfer bank', 'Tunai ke pengelola'];
  String _method = _methods.first;
  XFile? _proof;
  bool _showError = false;

  bool get _needsProof => _method == 'Transfer bank';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Bayar deposit ${formatRupiah(widget.deposit)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Metode pembayaran', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in _methods)
                  ChoiceChip(
                    label: Text(m),
                    selected: _method == m,
                    onSelected: (_) => setState(() {
                      _method = m;
                      _showError = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _needsProof
                  ? 'Transfer ke rekening pengelola, lalu unggah foto bukti '
                      'transfer.'
                  : 'Serahkan uang tunai ke pengelola. Foto kuitansi '
                      '(opsional).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_proof != null)
                  RemovablePhoto(
                    source: _proof!.path,
                    onRemove: () => setState(() => _proof = null),
                  )
                else
                  AddPhotoButton(
                    label: _needsProof ? 'Bukti\ntransfer' : 'Kuitansi',
                    onPressed: () async {
                      final f = await pickPhoto(context);
                      if (f != null && mounted) {
                        setState(() {
                          _proof = f;
                          _showError = false;
                        });
                      }
                    },
                  ),
              ],
            ),
            if (_showError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Unggah bukti transfer',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (_needsProof && _proof == null) {
              setState(() => _showError = true);
              return;
            }
            Navigator.pop<(String, XFile?)>(context, (_method, _proof));
          },
          child: const Text('Kirim'),
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile(this.log);

  final RenovationLog log;

  @override
  Widget build(BuildContext context) {
    final masuk = log.direction == LogDirection.masuk;
    final color = masuk ? AppColors.limeDark : Colors.orange.shade700;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              child: Icon(masuk ? Icons.south_west : Icons.north_east),
            ),
            title: Text('${log.item} · ${log.quantity}'),
            subtitle: Text([
              '${log.direction.label} ${formatTime(log.at)}',
              if (log.recordedBy.isNotEmpty) 'oleh ${log.recordedBy}',
              if (log.note.isNotEmpty) log.note,
            ].join(' · ')),
          ),
          if (log.photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
              child: PhotoStrip(photos: log.photos, size: 64),
            ),
        ],
      ),
    );
  }
}

typedef _LogInput = ({
  LogDirection direction,
  String item,
  String quantity,
  String note,
  List<XFile> photos,
});

class _LogDialog extends StatefulWidget {
  const _LogDialog();

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final _formKey = GlobalKey<FormState>();
  final _item = TextEditingController();
  final _qty = TextEditingController();
  final _note = TextEditingController();
  LogDirection _dir = LogDirection.masuk;
  final List<XFile> _photos = [];

  @override
  void dispose() {
    _item.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat barang'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<LogDirection>(
                segments: const [
                  ButtonSegment(
                    value: LogDirection.masuk,
                    label: Text('Masuk'),
                    icon: Icon(Icons.south_west),
                  ),
                  ButtonSegment(
                    value: LogDirection.keluar,
                    label: Text('Keluar'),
                    icon: Icon(Icons.north_east),
                  ),
                ],
                selected: {_dir},
                onSelectionChanged: (s) => setState(() => _dir = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _item,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Nama barang',
                  hintText: _dir == LogDirection.masuk
                      ? 'Contoh: Semen, keramik, pasir'
                      : 'Contoh: Puing, sisa material',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _qty,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Jumlah & satuan',
                  hintText: 'Contoh: 20 sak, 1 truk, 3 m³',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _note,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                  hintText: 'Contoh: plat kendaraan, nama sopir',
                ),
              ),
              Text('Foto barang (opsional, maks. $maxLogPhotos)',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    RemovablePhoto(
                      source: _photos[i].path,
                      onRemove: () => setState(() => _photos.removeAt(i)),
                    ),
                  if (_photos.length < maxLogPhotos)
                    AddPhotoButton(
                      onPressed: () async {
                        final f = await pickPhoto(context);
                        if (f != null && mounted) {
                          setState(() => _photos.add(f));
                        }
                      },
                    ),
                ],
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
              Navigator.pop<_LogInput>(context, (
                direction: _dir,
                item: _item.text.trim(),
                quantity: _qty.text.trim(),
                note: _note.text.trim(),
                photos: List.of(_photos),
              ));
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Dialog catatan. Mengembalikan teks (bisa kosong) atau null bila batal.
Future<String?> _promptNote(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  String? hint,
  bool required = false,
  bool destructive = false,
}) {
  final c = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: c,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: (v) =>
              required && (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, c.text.trim());
            }
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}
