import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../excel_io.dart';
import '../import_plan.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Import master data (cluster, tipe, blok, no. rumah) dan warga dari Excel
/// ke perumahan yang sedang aktif.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _fileName;
  ImportPlan? _plan;
  ImportResult? _result;
  bool _busy = false;
  String _progress = '';

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<void> _save(String fileName, Uint8List bytes) async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: _xlsxMime,
        dialogTitle: 'Simpan $fileName',
      );
      if (uri != null && mounted) showSnack(context, '$fileName disimpan');
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal menyimpan: ${describeError(e)}');
    }
  }

  String get _slug => store.estateName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  Future<void> _pick() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        dialogTitle: 'Pilih file Excel',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal memilih file: ${describeError(e)}');
      return;
    }
    if (file == null) return;
    setState(() {
      _busy = true;
      _progress = 'Membaca ${file.name}…';
      _result = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final plan = parseWorkbook(bytes, store, requireEmail: store.isFirebase);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _plan = plan;
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal membaca file: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final plan = _plan!;
    setState(() {
      _busy = true;
      _progress = 'Menyimpan…';
    });
    try {
      final result = await store.applyImport(plan, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _result = result;
        _plan = null;
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import dari Excel')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(store.estateName),
              subtitle: const Text('Data diimpor ke perumahan yang sedang aktif. '
                  'Pindah perumahan di Master Data bila perlu.'),
            ),
          ),
          const SizedBox(height: 16),
          _Step(
            number: 1,
            title: 'Siapkan file',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sheet "Rumah": Cluster, Tipe, Luas Bangunan, Luas Tanah, '
                  'Blok, No. Rumah (boleh rentang: 01-20). Sheet "Warga" '
                  '(opsional): Nama, Cluster, Blok, No. Rumah, No. HP, Email.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _save('template-nilaya-living.xlsx',
                              buildTemplate()),
                      icon: const Icon(Icons.download),
                      label: const Text('Unduh template'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || store.houses.isEmpty
                          ? null
                          : () => _save('data-$_slug.xlsx', buildExport(store)),
                      icon: const Icon(Icons.table_view),
                      label: const Text('Unduh data saat ini'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _Step(
            number: 2,
            title: 'Unggah file',
            child: FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName == null ? 'Pilih file .xlsx' : 'Pilih file lain'),
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_progress, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (_plan case final plan? when !_busy)
            _Step(
              number: 3,
              title: 'Periksa: $_fileName',
              child: _PlanPreview(plan: plan, onApply: _apply),
            ),
          if (_result case final result? when !_busy)
            _ResultView(
              result: result,
              onDownloadAccounts: result.accounts.any((a) => a.password != null)
                  ? () => _save('akun-warga-$_slug.xlsx',
                      buildAccountsSheet(result.accounts))
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.child});

  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.lime,
                foregroundColor: Colors.white,
                child: Text('$number',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.plan, required this.onApply});

  final ImportPlan plan;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = [
      ('Cluster baru', plan.clusters.length, Icons.holiday_village_outlined),
      ('Tipe rumah baru', plan.types.length, Icons.straighten),
      ('Blok baru', plan.blocks.length, Icons.grid_view),
      ('No. rumah baru', plan.houses.length, Icons.home_outlined),
      ('Warga baru', plan.residents.length, Icons.person_add_alt),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, n, icon) in counts)
              Chip(
                avatar: Icon(icon, size: 18),
                label: Text('$label: $n'),
              ),
          ],
        ),
        if (plan.existingHouses > 0 || plan.existingResidents > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sudah ada & dilewati: ${plan.existingHouses} rumah, '
              '${plan.existingResidents} warga.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (plan.errors.isNotEmpty)
          _MessageList(
            title: '${plan.errors.length} error — perbaiki file lalu unggah ulang',
            messages: plan.errors,
            color: scheme.error,
            icon: Icons.error_outline,
          ),
        if (plan.warnings.isNotEmpty)
          _MessageList(
            title: '${plan.warnings.length} peringatan',
            messages: plan.warnings,
            color: Colors.orange.shade800,
            icon: Icons.warning_amber_rounded,
          ),
        const SizedBox(height: 12),
        if (!plan.hasErrors && plan.isEmpty)
          Text('Tidak ada data baru — semua isi file sudah ada.',
              style: theme.textTheme.bodyMedium)
        else
          FilledButton.icon(
            onPressed: plan.hasErrors ? null : onApply,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Import sekarang'),
          ),
        if (plan.residents.isNotEmpty && store.isFirebase && !plan.hasErrors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Akun login dibuat untuk ${plan.residents.length} warga. '
              'Password sementara bisa diunduh setelah import.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.title,
    required this.messages,
    required this.color,
    required this.icon,
  });

  final String title;
  final List<String> messages;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const shown = 50;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        initiallyExpanded: messages.length <= 10,
        shape: const Border(),
        leading: Icon(icon, color: color),
        title: Text(title,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages.take(shown))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $m'),
            ),
          if (messages.length > shown)
            Text('… dan ${messages.length - shown} lainnya'),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, this.onDownloadAccounts});

  final ImportResult result;
  final VoidCallback? onDownloadAccounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = result.accounts.where((a) => a.error != null).toList();
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text('Import selesai',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${result.clusters} cluster, ${result.types} tipe, '
              '${result.blocks} blok, ${result.houses} no. rumah, '
              '${result.residents} warga ditambahkan.',
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${failed.length} warga gagal dibuat:',
                  style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700)),
              for (final a in failed) Text('• ${a.name} (${a.house}): ${a.error}'),
            ],
            if (onDownloadAccounts != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onDownloadAccounts,
                icon: const Icon(Icons.download),
                label: const Text('Unduh akun & password warga'),
              ),
              const SizedBox(height: 4),
              Text(
                'Simpan baik-baik dan bagikan ke masing-masing warga secara '
                'pribadi. Password tidak bisa ditampilkan lagi setelah layar '
                'ini ditutup.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
