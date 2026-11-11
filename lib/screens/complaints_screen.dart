import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../photo_widgets.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  ComplaintStatus? _filter;

  void _showDetail(Complaint c) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ComplaintDetailScreen(complaintId: c.id)));

  Future<void> _toggleFeature(bool enabled) async {
    final ok = await confirmSave(context,
        title: enabled ? 'Aktifkan fitur keluhan?' : 'Nonaktifkan fitur keluhan?',
        details: {
          'Perumahan': estateName,
          'Fitur keluhan warga': enabled ? 'Aktif' : 'Nonaktif',
        },
        note: enabled
            ? 'Warga bisa kembali membuat keluhan.'
            : 'Menu Keluhan disembunyikan dari aplikasi warga dan warga tidak '
                'bisa membuat keluhan baru. Keluhan lama tetap tersimpan.',
        action: enabled ? 'Ya, aktifkan' : 'Ya, nonaktifkan');
    if (!ok || !mounted) return;
    await runAction(context, store.setComplaintsEnabled(enabled),
        success: enabled
            ? 'Fitur keluhan diaktifkan'
            : 'Fitur keluhan dinonaktifkan untuk warga');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final isAdmin = store.isAdmin;
        var list = isAdmin
            ? store.complaints.toList()
            : store.complaints
                .where((c) => c.residentId == store.currentUser!.residentId)
                .toList();
        if (_filter != null) {
          list = list.where((c) => c.status == _filter).toList();
        }
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Scaffold(
          appBar:
              AppBar(title: Text(isAdmin ? 'Keluhan Warga' : 'Keluhan Saya')),
          floatingActionButton: isAdmin || !store.complaintsEnabled
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ComplaintFormScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Buat keluhan'),
                ),
          body: Column(
            children: [
              if (isAdmin &&
                  (store.can(AdminPermission.complaints) ||
                      store.can(AdminPermission.masterData)))
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  color: store.complaintsEnabled
                      ? null
                      : Theme.of(context).colorScheme.errorContainer,
                  child: SwitchListTile(
                    value: store.complaintsEnabled,
                    onChanged: _toggleFeature,
                    title: const Text('Fitur keluhan untuk warga'),
                    subtitle: Text(store.complaintsEnabled
                        ? 'Aktif · warga bisa membuat keluhan'
                        : 'Nonaktif · menu Keluhan disembunyikan dari warga'),
                  ),
                )
              else if (!isAdmin && !store.complaintsEnabled)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: const ListTile(
                    leading: Icon(Icons.block),
                    title: Text('Fitur keluhan sedang dinonaktifkan'),
                    subtitle: Text('Hubungi pengelola secara langsung.'),
                  ),
                ),
              FilterBar<ComplaintStatus>(
                options: {
                  null: 'Semua',
                  for (final s in ComplaintStatus.values) s: s.label,
                },
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        icon: Icons.sentiment_satisfied_alt,
                        message: 'Belum ada keluhan',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          final r = store.residentById(c.residentId);
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Flexible(child: Text(c.title)),
                                  if (c.photos.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Icon(Icons.photo_camera_outlined,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                isAdmin
                                    ? '${r?.name} (${r?.houseNo}) · ${c.category}'
                                    : '${c.category} · ${formatDate(c.createdAt)}',
                              ),
                              trailing: StatusChip(
                                  c.status.label, complaintColor(c.status)),
                              onTap: () => _showDetail(c),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ComplaintFormScreen extends StatefulWidget {
  const ComplaintFormScreen({super.key});

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _category = complaintCategories.first;
  final List<XFile> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await confirmSave(context,
        title: 'Kirim keluhan?',
        details: {
          'Judul': _title.text,
          'Kategori': _category,
          'Detail': _desc.text,
          'Foto': _photos.isEmpty ? 'Tanpa foto' : '${_photos.length} foto',
        },
        action: 'Ya, kirim');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final done = await runAction(
      context,
      store
          .addComplaint(
            _title.text.trim(),
            _desc.text.trim(),
            _category,
            photos: _photos,
          )
          .then((_) => true),
      success: 'Keluhan terkirim ke pengelola',
    );
    if (!mounted) return;
    if (done == true) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await pickPhoto(context);
    if (file != null && mounted) setState(() => _photos.add(file));
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Keluhan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Kategori', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final cat in complaintCategories)
                  ChoiceChip(
                    label: Text(cat),
                    selected: _category == cat,
                    onSelected: (_) => setState(() => _category = cat),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Judul',
                hintText: 'Contoh: Lampu jalan mati',
              ),
              validator: _required,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _desc,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Deskripsi',
                alignLabelWithHint: true,
              ),
              validator: _required,
            ),
            const SizedBox(height: 16),
            Text('Foto (opsional, maks. $maxComplaintPhotos)',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Stack(
                    children: [
                      PhotoThumb(source: _photos[i].path),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _saving
                                ? null
                                : () => setState(() => _photos.removeAt(i)),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < maxComplaintPhotos)
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _pickPhoto,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_a_photo_outlined),
                          SizedBox(height: 4),
                          Text('Tambah'),
                        ],
                      ),
                    ),
                  ),
              ],
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
              label: Text(_saving ? 'Mengirim...' : 'Kirim'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail keluhan: isi, foto, dan riwayat penanganan (status, catatan, foto).
class ComplaintDetailScreen extends StatelessWidget {
  const ComplaintDetailScreen({super.key, required this.complaintId});
  final String complaintId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.complaints.where((c) => c.id == complaintId).firstOrNull;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.report_problem_outlined,
                message: 'Keluhan tidak ditemukan'),
          );
        }
        final theme = Theme.of(context);
        final r = store.residentById(c.residentId);
        final canUpdate = store.can(AdminPermission.complaints);
        return Scaffold(
          appBar: AppBar(title: const Text('Detail keluhan')),
          floatingActionButton: canUpdate
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ComplaintUpdateScreen(complaint: c))),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Perbarui status'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              Row(
                children: [
                  StatusChip(c.status.label, complaintColor(c.status)),
                  const SizedBox(width: 8),
                  Text(c.category, style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 10),
              Text(c.title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  [
                    if (store.isAdmin) '${r?.name ?? ''} (${r?.houseNo ?? ''})',
                    '${formatDate(c.createdAt)} ${formatTime(c.createdAt)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(c.description, style: theme.textTheme.bodyLarge),
              if (c.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                PhotoStrip(photos: c.photos),
              ],
              const Divider(height: 40),
              Text('Riwayat penanganan', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _TimelineEntry(
                status: ComplaintStatus.baru,
                at: c.createdAt,
                title: 'Keluhan dibuat',
                by: r?.name ?? '',
                last: c.updates.isEmpty,
              ),
              for (var i = 0; i < c.updates.length; i++)
                _TimelineEntry(
                  status: c.updates[i].status,
                  at: c.updates[i].at,
                  title: 'Status: ${c.updates[i].status.label}',
                  by: c.updates[i].by,
                  note: c.updates[i].note,
                  photos: c.updates[i].photos,
                  last: i == c.updates.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.status,
    required this.at,
    required this.title,
    this.by = '',
    this.note = '',
    this.photos = const [],
    this.last = false,
  });

  final ComplaintStatus status;
  final DateTime at;
  final String title;
  final String by;
  final String note;
  final List<String> photos;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = complaintColor(status);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                        width: 2, color: theme.colorScheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                      [
                        '${formatDate(at)} ${formatTime(at)}',
                        if (by.isNotEmpty) by,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(note),
                  ],
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    PhotoStrip(photos: photos),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pengelola memperbarui penanganan keluhan: status, catatan, foto.
class ComplaintUpdateScreen extends StatefulWidget {
  const ComplaintUpdateScreen({super.key, required this.complaint});
  final Complaint complaint;

  @override
  State<ComplaintUpdateScreen> createState() => _ComplaintUpdateScreenState();
}

class _ComplaintUpdateScreenState extends State<ComplaintUpdateScreen> {
  late ComplaintStatus _status = widget.complaint.status;
  final _note = TextEditingController();
  final List<XFile> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.complaint;
    if (_status == c.status && _note.text.trim().isEmpty && _photos.isEmpty) {
      showSnack(context, 'Ubah status atau isi catatan/foto.');
      return;
    }
    final ok = await confirmSave(context,
        title: 'Perbarui keluhan?',
        details: {
          'Keluhan': c.title,
          'Status': _status == c.status
              ? _status.label
              : '${c.status.label} → ${_status.label}',
          'Catatan': _note.text,
          'Foto': _photos.isEmpty ? 'Tanpa foto' : '${_photos.length} foto',
        },
        note: 'Catatan & foto bisa dilihat warga pelapor.');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final done = await runAction(
      context,
      store
          .updateComplaintStatus(c.id, _status,
              note: _note.text, photos: _photos)
          .then((_) => true),
      success: 'Keluhan diperbarui: ${_status.label}',
    );
    if (!mounted) return;
    if (done == true) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Perbarui status')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.complaint.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('Status', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ComplaintStatus.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Catatan penanganan',
              hintText: 'Contoh: teknisi sudah mengganti lampu jalan',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('Foto (maks. $maxComplaintPhotos)',
              style: theme.textTheme.labelLarge),
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
              if (_photos.length < maxComplaintPhotos)
                AddPhotoButton(onPressed: () async {
                  final p = await pickPhoto(context);
                  if (p != null && mounted) setState(() => _photos.add(p));
                }),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
