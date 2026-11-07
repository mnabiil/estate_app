import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';
import 'house_picker.dart';

class ResidentsScreen extends StatefulWidget {
  const ResidentsScreen({super.key});

  @override
  State<ResidentsScreen> createState() => _ResidentsScreenState();
}

class _ResidentsScreenState extends State<ResidentsScreen> {
  String _query = '';

  Future<void> _addResident() async {
    final name = TextEditingController();
    String? houseId;
    final phone = TextEditingController();
    final email = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? req(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
        title: const Text('Tambah warga'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Nama kepala keluarga'),
                  validator: req,
                ),
                const SizedBox(height: 12),
                HousePickerField(
                  houseId: houseId,
                  onChanged: (v) => setDialog(() => houseId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. HP'),
                  validator: req,
                ),
                if (store.isFirebase)
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email (untuk login warga)',
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Email tidak valid'
                        : null,
                  ),
              ],
            ),
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
            child: const Text('Simpan'),
          ),
        ],
      ),
      ),
    );

    if (ok != true || !mounted) return;
    final n = name.text.trim();
    String? tempPassword;
    var failed = false;
    try {
      tempPassword = await store.addResident(
        n,
        houseId!,
        phone.text.trim(),
        email: store.isFirebase ? email.text.trim() : null,
      );
    } catch (e) {
      failed = true;
      if (mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    }
    if (failed || !mounted) return;
    if (tempPassword == null) {
      showSnack(context, 'Warga $n ditambahkan');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Akun $n dibuat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${email.text.trim()}'),
            const SizedBox(height: 8),
            const Text('Password sementara:'),
            SelectableText(tempPassword!,
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            const Text(
                'Berikan ke warga secara pribadi. Warga sebaiknya segera '
                'menggantinya lewat "Lupa password" di layar login.'),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Selesai')),
        ],
      ),
    );
    // Controller tidak di-dispose di sini karena dialog masih beranimasi saat
    // ditutup; akan dibersihkan oleh garbage collector.
  }

  void _showDetail(Resident r) {
    final bills = store.billsForResident(r.id)
      ..sort((a, b) => b.period.compareTo(a.period));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: CircleAvatar(child: Text(r.name[0])),
              title: Text(r.name, style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text([
                'Rumah ${r.houseNo}',
                if (r.houseId != null)
                  store
                      .clusterById(store.houseById(r.houseId!)?.clusterId ?? '')
                      ?.name,
                r.phone,
              ].whereType<String>().join(' · ')),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Riwayat IPL',
                  style: Theme.of(ctx).textTheme.labelLarge),
            ),
            for (final b in bills.take(3))
              ListTile(
                dense: true,
                title: Text(formatMonth(b.period)),
                trailing: StatusChip(b.status.label, billColor(b.status)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = _query.toLowerCase();
        final list = store.residents
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                r.houseNo.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => compareHouseNumber(a.houseNo, b.houseNo));

        return Scaffold(
          appBar: AppBar(title: Text('Data Warga (${store.residents.length})')),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Tambah warga',
            onPressed: _addResident,
            child: const Icon(Icons.person_add),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  hintText: 'Cari nama atau no. rumah',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        icon: Icons.person_search,
                        message: 'Warga tidak ditemukan')
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final r = list[i];
                          final unpaid = store.unpaidTotal(r.id);
                          return ListTile(
                            leading: CircleAvatar(child: Text(r.name[0])),
                            title: Text(r.name),
                            subtitle: Text('${r.houseNo} · ${r.phone}'),
                            trailing: unpaid > 0
                                ? StatusChip(
                                    'Tunggakan ${formatRupiah(unpaid)}',
                                    Colors.orange.shade700)
                                : StatusChip('Lancar', Colors.green.shade600),
                            onTap: () => _showDetail(r),
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
