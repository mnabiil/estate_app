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

  void _showDetail(Complaint c) {
    final r = store.residentById(c.residentId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                  '${c.category} · ${r?.name} (${r?.houseNo}) · ${formatDate(c.createdAt)}',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(c.description),
              if (c.photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: c.photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => PhotoThumb(
                      source: c.photos[i],
                      onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
                        builder: (_) =>
                            PhotoViewer(photos: c.photos, initial: i),
                      )),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (store.can(AdminPermission.complaints)) ...[
                Text('Ubah status', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in ComplaintStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: c.status == s,
                        onSelected: (_) async {
                          Navigator.pop(ctx);
                          final ok = await confirmSave(context,
                              title: 'Ubah status keluhan?',
                              details: {
                                'Keluhan': c.title,
                                'Status lama': c.status.label,
                                'Status baru': s.label,
                              });
                          if (!ok || !context.mounted) return;
                          await runAction(
                            context,
                            store.updateComplaintStatus(c.id, s),
                            success: 'Status keluhan: ${s.label}',
                          );
                        },
                      ),
                  ],
                ),
              ] else
                Row(
                  children: [
                    const Text('Status: '),
                    StatusChip(c.status.label, complaintColor(c.status)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
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
          floatingActionButton: isAdmin
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

