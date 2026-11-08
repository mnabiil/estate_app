import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pengumuman baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Judul'),
            ),
            TextField(
              controller: body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Isi pengumuman'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kirim')),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty && context.mounted) {
      await runAction(
        context,
        store.addAnnouncement(title.text.trim(), body.text.trim()),
        success: 'Pengumuman dikirim ke semua warga',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.announcements;
        return Scaffold(
          appBar: AppBar(title: const Text('Pengumuman')),
          floatingActionButton: store.can(AdminPermission.announcements)
              ? FloatingActionButton.extended(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.campaign),
                  label: const Text('Buat pengumuman'),
                )
              : null,
          body: list.isEmpty
              ? const EmptyState(
                  icon: Icons.campaign_outlined,
                  message: 'Belum ada pengumuman')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final a = list[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(formatDate(a.createdAt),
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Text(a.body),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
