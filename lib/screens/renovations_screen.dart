import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';

/// Warna & label status gabungan (status + tahap pekerjaan).
(String, Color) renovationBadge(Renovation r) {
  switch (r.status) {
    case RenovationStatus.diajukan:
      return r.depositStatus == DepositStatus.belumBayar
          ? ('Menunggu deposit', Colors.orange.shade700)
          : ('Menunggu persetujuan', Colors.blue.shade600);
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
          appBar: AppBar(title: const Text('Ijin Renovasi')),
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
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: list.length,
                        itemBuilder: (context, i) =>
                            _RenovationCard(list[i], showResident: isAdmin),
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
  bool _saving = false;
  bool _agree = false;

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
        showSnack(context, 'Setujui ketentuan deposit terlebih dahulu.');
      }
      return;
    }
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
      ).then((_) => true),
      success: 'Ijin renovasi diajukan. Silakan bayar deposit ke pengelola.',
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
                labelText: 'Uraian pekerjaan',
                hintText: 'Contoh: ganti keramik dapur, cat ulang ruang tamu',
                alignLabelWithHint: true,
              ),
              validator: _required,
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
                    'Bayar deposit ke pengelola sebelum pekerjaan dimulai. '
                    'Ijin disetujui setelah deposit diterima. Deposit '
                    'dikembalikan setelah renovasi selesai, dan dapat dipotong '
                    'bila ada kerusakan fasilitas umum, sisa material/puing, '
                    'atau pelanggaran tata tertib.',
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
    await runAction(context, store.extendRenovation(r.id, picked),
        success: 'Diperpanjang sampai ${formatDate(picked)}');
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
    await runAction(
      context,
      store.refundDeposit(r.id, n, note: note.text.trim()),
      success: 'Deposit ${formatRupiah(n)} dikembalikan',
    );
  }

  Future<void> _addLog(BuildContext context, Renovation r) async {
    final result = await showDialog<_LogInput>(
      context: context,
      builder: (_) => const _LogDialog(),
    );
    if (result == null || !context.mounted) return;
    await runAction(
      context,
      store.addRenovationLog(
        r.id,
        direction: result.direction,
        item: result.item,
        quantity: result.quantity,
        note: result.note,
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
        final canLog = r.status == RenovationStatus.disetujui;

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
              if (r.status == RenovationStatus.disetujui) _Progress(r),
              if (r.adminNote.isNotEmpty)
                _InfoRow(Icons.sticky_note_2_outlined, 'Catatan pengelola',
                    r.adminNote),
              const SizedBox(height: 12),
              _DepositCard(r),
              // ----- aksi pengelola -----
              if (isAdmin) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (r.status == RenovationStatus.diajukan &&
                        r.depositStatus == DepositStatus.belumBayar)
                      FilledButton.icon(
                        onPressed: () => runAction(
                            context, store.markDepositPaid(r.id),
                            success: 'Deposit dicatat diterima'),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Deposit diterima'),
                      ),
                    if (r.status == RenovationStatus.diajukan)
                      FilledButton.icon(
                        onPressed: r.depositStatus == DepositStatus.dibayar
                            ? () => _approve(context, r)
                            : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Setujui'),
                      ),
                    if (r.status == RenovationStatus.diajukan)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error),
                        onPressed: () => _reject(context, r),
                        icon: const Icon(Icons.close),
                        label: const Text('Tolak'),
                      ),
                    if (r.status == RenovationStatus.disetujui) ...[
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
                    if (r.depositStatus == DepositStatus.dibayar &&
                        !r.isActive)
                      FilledButton.icon(
                        onPressed: () => _refund(context, r),
                        icon: const Icon(Icons.undo),
                        label: const Text('Kembalikan deposit'),
                      ),
                  ],
                ),
                if (r.status == RenovationStatus.diajukan &&
                    r.depositStatus == DepositStatus.belumBayar)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Ijin bisa disetujui setelah deposit diterima.',
                        style: theme.textTheme.bodySmall),
                  ),
              ] else if (r.status == RenovationStatus.diajukan &&
                  r.depositStatus == DepositStatus.belumBayar) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => runAction(
                      context, store.cancelRenovation(r.id),
                      success: 'Pengajuan dibatalkan'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Batalkan pengajuan'),
                ),
              ],
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
                          'masuk atau keluar (puing, sisa material).'
                      : 'Catatan barang dimulai setelah ijin disetujui.',
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
    final lines = <String>[
      if (r.depositPaidAt != null) 'Diterima ${formatDate(r.depositPaidAt!)}',
      if (r.depositStatus == DepositStatus.dikembalikan)
        'Dikembalikan ${formatRupiah(r.depositRefund ?? 0)}'
            '${r.depositRefundedAt != null ? ' pada ${formatDate(r.depositRefundedAt!)}' : ''}'
            '${(r.depositRefund ?? 0) < r.deposit ? ' (dipotong ${formatRupiah(r.deposit - (r.depositRefund ?? 0))})' : ''}',
      if (r.depositStatus == DepositStatus.belumBayar)
        'Bayar ke pengelola agar ijin dapat diproses.',
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.savings_outlined),
        title: Text('Deposit ${formatRupiah(r.deposit)}'),
        subtitle: Text([r.depositStatus.label, ...lines].join('\n')),
        isThreeLine: lines.isNotEmpty,
        trailing: Icon(
          switch (r.depositStatus) {
            DepositStatus.belumBayar => Icons.hourglass_empty,
            DepositStatus.dibayar => Icons.lock_outline,
            DepositStatus.dikembalikan => Icons.check_circle_outline,
          },
          color: theme.colorScheme.primary,
        ),
      ),
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
      child: ListTile(
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
    );
  }
}

typedef _LogInput = ({
  LogDirection direction,
  String item,
  String quantity,
  String note,
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
