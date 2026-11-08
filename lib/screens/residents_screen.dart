import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';
import 'house_picker.dart';
import 'household_screen.dart';
import 'registrations_screen.dart';

class ResidentsScreen extends StatefulWidget {
  const ResidentsScreen({super.key});

  @override
  State<ResidentsScreen> createState() => _ResidentsScreenState();
}

class _ResidentsScreenState extends State<ResidentsScreen> {
  String _query = '';
  bool _onlyUnlinked = false;

  bool _isLinked(Resident r) =>
      r.houseId != null && store.houseById(r.houseId!) != null;

  /// Atur / pindah rumah warga (termasuk warga lama yang nomor rumahnya
  /// dulu diketik manual).
  Future<void> _assignHouse(Resident r) async {
    final linked = _isLinked(r);
    // Warga lama: tawarkan rumah yang labelnya cocok dengan catatan lama.
    String? houseId = linked ? r.houseId : null;
    if (houseId == null) {
      final match = store.houseMatchingLabel(r.houseNo);
      final occupant = match == null ? null : store.residentOfHouse(match.id);
      if (match != null && (occupant == null || occupant.id == r.id)) {
        houseId = match.id;
      }
    }
    final suggested = !linked && houseId != null;
    final formKey = GlobalKey<FormState>();

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(linked ? 'Pindah rumah' : 'Atur rumah'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(r.name, style: Theme.of(ctx).textTheme.titleMedium),
                  Text(
                    linked
                        ? 'Saat ini: ${r.houseNo}'
                        : 'Tercatat (diketik manual): "${r.houseNo}"',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (suggested)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Rumah yang cocok sudah dipilihkan. Periksa lalu simpan.',
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.primary,
                            fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                  HousePickerField(
                    houseId: houseId,
                    allowEstateChange: false,
                    exceptResidentId: r.id,
                    onChanged: (v) => setDialog(() => houseId = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, houseId);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (linked && picked == r.houseId) return;
    final h = store.houseById(picked)!;
    await runAction(
      context,
      store.assignHouse(r.id, picked),
      success: '${r.name} kini di rumah ${store.houseLabel(h)}',
    );
  }

  Future<void> _autoLink() async {
    final result = await runAction(context, store.autoLinkResidents());
    if (result == null || !mounted) return;
    final (linked, remaining) = result;
    showSnack(
      context,
      linked == 0
          ? 'Tidak ada nomor rumah yang cocok dengan master. '
              'Atur $remaining warga secara manual.'
          : '$linked warga terhubung otomatis'
              '${remaining > 0 ? ', $remaining perlu diatur manual' : ''}.',
    );
    if (remaining > 0) setState(() => _onlyUnlinked = true);
  }

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
                if (store.houseById(r.houseId ?? '') case final h?)
                  store.houseTypeOf(h)?.name,
                r.phone,
              ].whereType<String>().join(' · ')),
            ),
            if (store.can(AdminPermission.residents))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _isLinked(r)
                  ? OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _assignHouse(r);
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Pindah rumah'),
                    )
                  : FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _assignHouse(r);
                      },
                      icon: const Icon(Icons.add_home_outlined),
                      label: const Text('Atur rumah dari master data'),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => HouseholdScreen(residentId: r.id)));
                },
                icon: const Icon(Icons.family_restroom),
                label: Text(
                    'Anggota rumah (${store.membersOf(r.id).length})'),
              ),
            ),
            if (store.isFirebase && store.can(AdminPermission.residents))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    resetResidentPasswordFlow(context,
                        name: r.name, residentId: r.id);
                  },
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reset password'),
                ),
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
        final unlinked = store.unlinkedResidents.length;
        if (unlinked == 0) _onlyUnlinked = false;
        final list = store.residents
            .where((r) =>
                (!_onlyUnlinked || !_isLinked(r)) &&
                (r.name.toLowerCase().contains(q) ||
                    r.houseNo.toLowerCase().contains(q)))
            .toList()
          ..sort((a, b) => compareHouseNumber(a.houseNo, b.houseNo));

        return Scaffold(
          appBar: AppBar(title: Text('Data Warga (${store.residents.length})')),
          floatingActionButton: store.can(AdminPermission.residents)
              ? FloatingActionButton(
                  tooltip: 'Tambah warga',
                  onPressed: _addResident,
                  child: const Icon(Icons.person_add),
                )
              : null,
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
              const OtherEstatePendingBanner(),
              if (store.pendingRegistrations.isNotEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: Text(
                        '${store.pendingRegistrations.length} pendaftaran warga '
                        'menunggu verifikasi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RegistrationsScreen())),
                  ),
                ),
              if (unlinked > 0 && store.can(AdminPermission.residents))
                _UnlinkedBanner(
                  count: unlinked,
                  filtering: _onlyUnlinked,
                  onToggleFilter: () =>
                      setState(() => _onlyUnlinked = !_onlyUnlinked),
                  onAutoLink: _autoLink,
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
                            subtitle: _isLinked(r)
                                ? Text('${r.houseNo} · ${r.phone}')
                                : Text.rich(TextSpan(children: [
                                    TextSpan(text: '${r.houseNo} · '),
                                    TextSpan(
                                      text: 'belum terhubung',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ])),
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

class _UnlinkedBanner extends StatelessWidget {
  const _UnlinkedBanner({
    required this.count,
    required this.filtering,
    required this.onToggleFilter,
    required this.onAutoLink,
  });

  final int count;
  final bool filtering;
  final VoidCallback onToggleFilter;
  final VoidCallback onAutoLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_off, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$count warga belum terhubung ke master rumah',
                    style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: onToggleFilter,
                  child: Text(filtering ? 'Tampilkan semua' : 'Tampilkan'),
                ),
                TextButton(
                  onPressed: onAutoLink,
                  child: const Text('Hubungkan otomatis'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
