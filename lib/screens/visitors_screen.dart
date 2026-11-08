import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

class VisitorsScreen extends StatelessWidget {
  const VisitorsScreen({super.key});

  static void showCode(BuildContext context, Visitor v) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.qr_code_2, size: 40),
        title: const Text('Kode akses tamu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              v.code,
              style: Theme.of(ctx)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 6),
            ),
            const SizedBox(height: 8),
            Text('${v.name} · ${formatDate(v.visitDate)}',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Bagikan kode ini ke tamu untuk ditunjukkan ke satpam.',
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final isAdmin = store.isAdmin;
        final list = (isAdmin
            ? store.visitors.toList()
            : store.visitors
                .where((v) => v.residentId == store.currentUser!.residentId)
                .toList())
          ..sort((a, b) => b.visitDate.compareTo(a.visitDate));

        return Scaffold(
          appBar: AppBar(title: Text(isAdmin ? 'Log Tamu' : 'Tamu Saya')),
          floatingActionButton: isAdmin
              ? null
              : FloatingActionButton.extended(
                  onPressed: () async {
                    final v = await Navigator.of(context).push<Visitor>(
                      MaterialPageRoute(
                          builder: (_) => const VisitorFormScreen()),
                    );
                    if (v != null && context.mounted) showCode(context, v);
                  },
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Daftarkan tamu'),
                ),
          body: list.isEmpty
              ? const EmptyState(
                  icon: Icons.badge_outlined,
                  message: 'Belum ada tamu terdaftar')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final v = list[i];
                    final host = store.residentById(v.residentId);
                    final inAt = v.checkedInAt;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(v.name),
                        subtitle: Text([
                          if (isAdmin) 'Ke ${host?.name} (${host?.houseNo})',
                          '${v.purpose} · ${formatDate(v.visitDate)} · Kode ${v.code}',
                        ].join('\n')),
                        isThreeLine: isAdmin,
                        trailing: inAt != null
                            ? StatusChip('Masuk ${formatTime(inAt)}',
                                Colors.green.shade600)
                            : store.can(AdminPermission.visitors)
                                ? FilledButton.tonal(
                                    onPressed: () => runAction(
                                      context,
                                      store.checkInVisitor(v.id),
                                      success: '${v.name} sudah masuk',
                                    ),
                                    child: const Text('Check-in'),
                                  )
                                : StatusChip('Menunggu', Colors.blue.shade600),
                        onTap: isAdmin ? null : () => showCode(context, v),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class VisitorFormScreen extends StatefulWidget {
  const VisitorFormScreen({super.key});

  @override
  State<VisitorFormScreen> createState() => _VisitorFormScreenState();
}

class _VisitorFormScreenState extends State<VisitorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _purpose = TextEditingController();
  late DateTime _date = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today(),
      lastDate: _today().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  bool _saving = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final v = await runAction(
      context,
      store.addVisitor(_name.text.trim(), _purpose.text.trim(), _date),
    );
    if (!mounted) return;
    if (v == null) {
      setState(() => _saving = false);
      return;
    }
    // Kode akses ditampilkan oleh layar daftar tamu.
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftarkan Tamu')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nama tamu',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _purpose,
              decoration: const InputDecoration(
                labelText: 'Keperluan',
                hintText: 'Contoh: Silaturahmi, antar paket',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              leading: const Icon(Icons.event),
              title: const Text('Tanggal kunjungan'),
              subtitle: Text(formatDate(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.qr_code),
              label: const Text('Buat kode akses'),
            ),
          ],
        ),
      ),
    );
  }
}
