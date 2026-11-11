import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../photo_widgets.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

/// Daftar pengumuman ala portal berita. Warga hanya melihat pengumuman yang
/// masih berlaku; pengelola melihat semua (yang berakhir diberi tanda).
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.visibleAnnouncements;
        return Scaffold(
          appBar: AppBar(title: const Text('Pengumuman')),
          floatingActionButton: store.can(AdminPermission.announcements)
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AnnouncementFormScreen())),
                  icon: const Icon(Icons.campaign),
                  label: const Text('Buat pengumuman'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: store.refresh,
            child: list.isEmpty
                ? const EmptyState(
                    scrollable: true,
                    icon: Icons.campaign_outlined,
                    message: 'Belum ada pengumuman')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        AnnouncementCard(list[i], featured: i == 0),
                  ),
          ),
        );
      },
    );
  }
}

void openAnnouncement(BuildContext context, Announcement a) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(announcementId: a.id)));

/// Kartu pengumuman: foto sampul (bila ada), judul, cuplikan, tanggal.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard(this.a, {super.key, this.featured = false});
  final Announcement a;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = a.photoUrl;
    final ended = !a.isActiveOn(DateTime.now());
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => openAnnouncement(context, a),
        child: Opacity(
          opacity: ended ? 0.6 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photo != null && photo.isNotEmpty)
                AspectRatio(
                  aspectRatio: featured ? 16 / 9 : 21 / 9,
                  child: photoImage(photo),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Meta(a),
                    const SizedBox(height: 6),
                    Text(a.title,
                        style: (featured
                                ? theme.textTheme.titleLarge
                                : theme.textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (a.body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(a.body,
                          maxLines: featured ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 8),
                    Text('Baca selengkapnya',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
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

class _Meta extends StatelessWidget {
  const _Meta(this.a);
  final Announcement a;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ended = !a.isActiveOn(DateTime.now());
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(formatDate(a.createdAt), style: theme.textTheme.bodySmall),
        if (a.until != null)
          StatusChip(
            ended ? 'Berakhir' : 'Berlaku s/d ${formatDate(a.until!)}',
            ended ? Colors.grey.shade600 : Colors.blue.shade600,
          ),
      ],
    );
  }
}

/// Tampilan artikel: foto besar, judul, info, dan isi lengkap.
class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.announcementId});
  final String announcementId;

  Future<void> _delete(BuildContext context, Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus pengumuman?'),
        content: Text('"${a.title}" akan dihapus untuk semua warga '
            'perumahan ini.'),
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
    final done = await runAction(
        context, store.deleteAnnouncement(a.id).then((_) => true),
        success: 'Pengumuman dihapus');
    if (done == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final a = store.announcementById(announcementId);
        if (a == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.campaign_outlined,
                message: 'Pengumuman tidak ditemukan'),
          );
        }
        final theme = Theme.of(context);
        final photo = a.photoUrl;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Pengumuman'),
            actions: [
              if (store.can(AdminPermission.announcements))
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, a),
                ),
            ],
          ),
          body: ListView(
            children: [
              if (photo != null && photo.isNotEmpty)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PhotoViewer(photos: [photo]))),
                  child: AspectRatio(
                      aspectRatio: 16 / 9, child: photoImage(photo)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.campaign_outlined,
                            size: 16, color: theme.colorScheme.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            [
                              a.createdBy.isNotEmpty ? a.createdBy : 'Pengelola',
                              estateName,
                              '${formatDate(a.createdAt)} ${formatTime(a.createdAt)}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (a.until != null) ...[
                      const SizedBox(height: 8),
                      _Meta(a),
                    ],
                    const Divider(height: 32),
                    SelectableText(a.body,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Form pengumuman: judul, isi, foto sampul, tanggal berakhir, perumahan.
class AnnouncementFormScreen extends StatefulWidget {
  const AnnouncementFormScreen({super.key});

  @override
  State<AnnouncementFormScreen> createState() => _AnnouncementFormScreenState();
}

class _AnnouncementFormScreenState extends State<AnnouncementFormScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  XFile? _photo;
  DateTime? _until;
  Set<String> _targets = {
    if (store.activeEstateId != null) store.activeEstateId!
  };
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickUntil() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'Berlaku sampai',
    );
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Judul wajib diisi');
      return;
    }
    if (_targets.isEmpty) {
      showSnack(context, 'Pilih minimal satu perumahan');
      return;
    }
    final confirmed = await confirmSave(context,
        title: 'Kirim pengumuman?',
        details: {
          'Judul': _title.text,
          'Isi': _body.text,
          'Foto': _photo == null ? 'Tanpa foto' : 'Ada foto sampul',
          'Berlaku': _until == null
              ? 'Tanpa batas waktu'
              : 'Sampai ${formatDate(_until!)}',
          'Perumahan':
              [for (final id in _targets) store.estateNameOf(id)].join(', '),
        },
        note: 'Notifikasi dikirim ke semua warga di perumahan terpilih.',
        action: 'Ya, kirim');
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      store
          .addAnnouncement(_title.text, _body.text,
              estateIds: _targets.toList(), until: _until, photo: _photo)
          .then((_) => true),
      success: _targets.length > 1
          ? 'Pengumuman dikirim ke ${_targets.length} perumahan'
          : 'Pengumuman dikirim ke semua warga',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = _photo;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengumuman baru')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (photo != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                      aspectRatio: 16 / 9, child: photoImage(photo.path)),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: 'Hapus foto',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _photo = null),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: () async {
                final p = await pickPhoto(context);
                if (p != null && mounted) setState(() => _photo = p);
              },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Tambah foto sampul (opsional)'),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Judul'),
          ),
          TextField(
            controller: _body,
            minLines: 6,
            maxLines: 16,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Isi pengumuman', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_until == null
                ? 'Tanpa batas waktu'
                : 'Berlaku sampai ${formatDate(_until!)}'),
            subtitle: const Text(
                'Setelah tanggal ini pengumuman tidak tampil lagi untuk warga'),
            trailing: _until == null
                ? TextButton(onPressed: _pickUntil, child: const Text('Atur'))
                : IconButton(
                    tooltip: 'Hapus batas waktu',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _until = null),
                  ),
            onTap: _pickUntil,
          ),
          if (store.estates.length > 1) ...[
            const SizedBox(height: 8),
            Text('Kirim ke perumahan', style: theme.textTheme.labelLarge),
            EstateChecklist(
              selected: _targets,
              onChanged: (v) => setState(() => _targets = v),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Kirim pengumuman'),
          ),
        ],
      ),
    );
  }
}
