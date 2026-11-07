import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';

/// Master perumahan (khusus pengelola): profil perumahan, lalu
/// Cluster > Blok > No. rumah. Data ini menjadi daftar pilihan saat
/// menambah warga, jadi tidak perlu mengetik nomor rumah manual.
class MasterDataScreen extends StatelessWidget {
  const MasterDataScreen({super.key});

  Future<void> _editEstate(BuildContext context) async {
    final name = TextEditingController(text: store.estateName);
    final address = TextEditingController(text: store.estateAddress);
    final fee = TextEditingController(text: '${store.fee}');
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profil perumahan'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Nama perumahan'),
                  validator: (v) => _requiredMax(v, 100),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: address,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                  validator: (v) =>
                      (v ?? '').length > 300 ? 'Maks. 300 karakter' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: fee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tarif IPL per bulan',
                    prefixText: 'Rp ',
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').replaceAll('.', ''));
                    return (n == null || n <= 0) ? 'Isi angka > 0' : null;
                  },
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
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      store.updateEstate(
        name: name.text.trim(),
        address: address.text.trim(),
        fee: int.parse(fee.text.replaceAll('.', '')),
      ),
      success: 'Profil perumahan disimpan',
    );
  }

  Future<void> _editCluster(BuildContext context, [Cluster? c]) async {
    final name = await promptText(
      context,
      title: c == null ? 'Tambah cluster' : 'Ubah nama cluster',
      label: 'Nama cluster',
      hint: 'Contoh: Cluster Anggrek',
      initial: c?.name,
      maxLength: 60,
    );
    if (name == null || !context.mounted) return;
    await runAction(context, store.saveCluster(name, id: c?.id),
        success: c == null ? 'Cluster $name ditambahkan' : 'Nama disimpan');
  }

  Future<void> _editType(BuildContext context, [HouseType? t]) async {
    final name = TextEditingController(text: t?.name);
    final lb = TextEditingController(text: t?.buildingArea?.toString() ?? '');
    final lt = TextEditingController(text: t?.landArea?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    String? area(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final n = int.tryParse(v.trim());
      return (n == null || n <= 0 || n > 100000) ? 'Angka tidak valid' : null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t == null ? 'Tambah tipe rumah' : 'Ubah tipe rumah'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama tipe',
                    hintText: 'Contoh: Tipe 36/72',
                  ),
                  validator: (v) => _requiredMax(v, 40),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: lb,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Luas bangunan',
                          suffixText: 'm²',
                        ),
                        validator: area,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: lt,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Luas tanah',
                          suffixText: 'm²',
                        ),
                        validator: area,
                      ),
                    ),
                  ],
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
    );
    if (ok != true || !context.mounted) return;
    final n = name.text.trim();
    await runAction(
      context,
      store.saveHouseType(
        n,
        id: t?.id,
        buildingArea: int.tryParse(lb.text.trim()),
        landArea: int.tryParse(lt.text.trim()),
      ),
      success: t == null ? '$n ditambahkan' : 'Tipe disimpan',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final clusters = store.sortedClusters;
        final types = store.sortedHouseTypes;
        final occupied = store.residents.where((r) => r.houseId != null).length;

        return Scaffold(
          appBar: AppBar(title: const Text('Master Data Perumahan')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editCluster(context),
            icon: const Icon(Icons.add),
            label: const Text('Cluster'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_city),
                  title: Text(store.estateName),
                  subtitle: Text([
                    if (store.estateAddress.isNotEmpty) store.estateAddress,
                    'IPL ${formatRupiah(store.fee)}/bulan',
                  ].join('\n')),
                  isThreeLine: store.estateAddress.isNotEmpty,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editEstate(context),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${clusters.length} cluster · ${store.blocks.length} blok · '
                  '${store.houses.length} rumah · $occupied terisi',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child:
                        Text('Tipe rumah', style: theme.textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    onPressed: () => _editType(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Tipe'),
                  ),
                ],
              ),
              if (types.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Belum ada tipe rumah (opsional), mis. Tipe 36/72.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final t in types)
                _MasterTile(
                  icon: Icons.straighten,
                  title: t.name,
                  subtitle: [
                    if (t.areaText.isNotEmpty) t.areaText,
                    '${store.houses.where((h) => h.typeId == t.id).length} rumah',
                  ].join(' · '),
                  onTap: () => _editType(context, t),
                  editLabel: 'Ubah',
                  onEdit: () => _editType(context, t),
                  onDelete: () => _confirmDelete(
                    context,
                    'Hapus ${t.name}?',
                    () => store.deleteHouseType(t.id),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Cluster', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              if (clusters.isEmpty)
                const EmptyState(
                  icon: Icons.holiday_village_outlined,
                  message: 'Belum ada cluster.\n'
                      'Tambahkan cluster, lalu blok dan nomor rumahnya.',
                ),
              for (final c in clusters)
                _MasterTile(
                  icon: Icons.holiday_village_outlined,
                  title: c.name,
                  subtitle: _countText(
                    blocks: store.blocksOf(c.id).length,
                    houses: store.houses.where((h) => h.clusterId == c.id),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ClusterScreen(clusterId: c.id))),
                  onEdit: () => _editCluster(context, c),
                  onDelete: () => _confirmDelete(
                    context,
                    'Hapus ${c.name}?',
                    () => store.deleteCluster(c.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ClusterScreen extends StatelessWidget {
  const ClusterScreen({super.key, required this.clusterId});

  final String clusterId;

  Future<void> _editBlock(BuildContext context, [HouseBlock? b]) async {
    final name = await promptText(
      context,
      title: b == null ? 'Tambah blok' : 'Ubah nama blok',
      label: 'Nama blok',
      hint: 'Contoh: A1',
      initial: b?.name,
      maxLength: 20,
    );
    if (name == null || !context.mounted) return;
    await runAction(context, store.saveBlock(clusterId, name, id: b?.id),
        success: b == null ? 'Blok $name ditambahkan' : 'Nama disimpan');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cluster = store.clusterById(clusterId);
        if (cluster == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.search_off, message: 'Cluster tidak ditemukan'),
          );
        }
        final blocks = store.blocksOf(clusterId);
        return Scaffold(
          appBar: AppBar(title: Text(cluster.name)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editBlock(context),
            icon: const Icon(Icons.add),
            label: const Text('Blok'),
          ),
          body: blocks.isEmpty
              ? const EmptyState(
                  icon: Icons.grid_view,
                  message: 'Belum ada blok di cluster ini.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final b in blocks)
                      _MasterTile(
                        icon: Icons.grid_view,
                        title: 'Blok ${b.name}',
                        subtitle: _countText(houses: store.housesOf(b.id)),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => BlockScreen(blockId: b.id))),
                        onEdit: () => _editBlock(context, b),
                        onDelete: () => _confirmDelete(
                          context,
                          'Hapus blok ${b.name}?',
                          () => store.deleteBlock(b.id),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class BlockScreen extends StatelessWidget {
  const BlockScreen({super.key, required this.blockId});

  final String blockId;

  Future<void> _addHouses(BuildContext context) async {
    final result = await showDialog<(List<String>, String?)>(
      context: context,
      builder: (_) => const _AddHousesDialog(),
    );
    if (result == null || !context.mounted) return;
    final (numbers, typeId) = result;
    if (numbers.isEmpty) return;
    final added = await runAction(
        context, store.addHouses(blockId, numbers, typeId: typeId));
    if (added == null || !context.mounted) return;
    final skipped = numbers.length - added;
    showSnack(
      context,
      '$added nomor rumah ditambahkan'
      '${skipped > 0 ? ' ($skipped sudah ada, dilewati)' : ''}',
    );
  }

  Future<void> _setTypeForBlock(BuildContext context) async {
    final houses = store.housesOf(blockId);
    if (houses.isEmpty) return;
    final picked = await pickHouseType(context,
        title: 'Tipe untuk semua rumah di blok ini');
    if (picked == null || !context.mounted) return;
    await runAction(
      context,
      store.setHouseType(houses.map((h) => h.id), picked.typeId),
      success: 'Tipe ${houses.length} rumah diperbarui',
    );
  }

  void _showHouse(BuildContext context, House h) {
    final r = store.residentOfHouse(h.id);
    final type = store.houseTypeById(h.typeId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Rumah ${store.houseLabel(h)}',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(store.clusterById(h.clusterId)?.name ?? ''),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.straighten),
                title: Text(type?.name ?? 'Tipe belum diatur'),
                subtitle:
                    type?.areaText.isNotEmpty == true ? Text(type!.areaText) : null,
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await pickHouseType(ctx,
                        title: 'Tipe rumah ${store.houseLabel(h)}',
                        selected: h.typeId);
                    if (picked == null || !ctx.mounted) return;
                    Navigator.pop(ctx);
                    await runAction(
                        context, store.setHouseType([h.id], picked.typeId),
                        success: 'Tipe disimpan');
                  },
                  child: const Text('Ubah'),
                ),
              ),
              const SizedBox(height: 8),
              Text(r == null
                  ? 'Belum berpenghuni.'
                  : 'Ditempati ${r.name} · ${r.phone}'),
              const SizedBox(height: 24),
              if (r == null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    runAction(context, store.deleteHouse(h.id),
                        success: 'Rumah ${store.houseLabel(h)} dihapus');
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus nomor rumah'),
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
        final block = store.blockById(blockId);
        if (block == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.search_off, message: 'Blok tidak ditemukan'),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        final houses = store.housesOf(blockId);
        return Scaffold(
          appBar: AppBar(
            title: Text('Blok ${block.name}'),
            actions: [
              if (houses.isNotEmpty && store.houseTypes.isNotEmpty)
                IconButton(
                  tooltip: 'Atur tipe semua rumah',
                  icon: const Icon(Icons.straighten),
                  onPressed: () => _setTypeForBlock(context),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addHouses(context),
            icon: const Icon(Icons.add),
            label: const Text('No. rumah'),
          ),
          body: houses.isEmpty
              ? const EmptyState(
                  icon: Icons.home_outlined,
                  message: 'Belum ada nomor rumah.\n'
                      'Tambahkan sekaligus, mis. nomor 1 sampai 20.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 110,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: houses.length,
                  itemBuilder: (context, i) {
                    final h = houses[i];
                    final r = store.residentOfHouse(h.id);
                    final filled = r != null;
                    return Material(
                      color: filled
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showHouse(context, h),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                filled ? Icons.home : Icons.home_outlined,
                                color: filled
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                h.number,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: filled
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                ),
                              ),
                              if (store.houseTypeById(h.typeId) case final t?)
                                Text(
                                  t.name.replaceFirst(
                                      RegExp(r'^tipe\s*', caseSensitive: false),
                                      ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: filled
                                        ? AppColors.lime
                                        : scheme.primary,
                                  ),
                                ),
                              Text(
                                r?.name.split(' ').first ?? 'Kosong',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: filled
                                      ? scheme.onPrimary.withValues(alpha: 0.85)
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
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

/// Dialog menambah nomor rumah: rentang (mis. 1-20) atau manual (12A, 12B).
class _AddHousesDialog extends StatefulWidget {
  const _AddHousesDialog();

  @override
  State<_AddHousesDialog> createState() => _AddHousesDialogState();
}

class _AddHousesDialogState extends State<_AddHousesDialog> {
  final _formKey = GlobalKey<FormState>();
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '10');
  final _manual = TextEditingController();
  bool _range = true;
  bool _pad = true;
  String? _typeId;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _manual.dispose();
    super.dispose();
  }

  String? _int(String? v) =>
      int.tryParse(v ?? '') == null ? 'Isi angka' : null;

  List<String> _numbers() {
    if (_range) {
      final a = int.parse(_from.text);
      final b = int.parse(_to.text);
      return [
        for (var n = a; n <= b; n++) _pad ? n.toString().padLeft(2, '0') : '$n',
      ];
    }
    return _manual.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah nomor rumah'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Rentang')),
                  ButtonSegment(value: false, label: Text('Manual')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 16),
              if (_range) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _from,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Dari'),
                        validator: _int,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _to,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Sampai'),
                        validator: (v) {
                          final e = _int(v);
                          if (e != null) return e;
                          final a = int.tryParse(_from.text);
                          final b = int.parse(v!);
                          if (a != null && b < a) return 'Harus ≥ dari';
                          if (a != null && b - a >= 300) return 'Maks. 300';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Awali dengan nol (01, 02, …)'),
                  value: _pad,
                  onChanged: (v) => setState(() => _pad = v),
                ),
              ] else
                TextFormField(
                  controller: _manual,
                  decoration: const InputDecoration(
                    labelText: 'Nomor rumah',
                    hintText: 'Pisahkan dengan koma: 12A, 12B, 15',
                  ),
                  validator: (v) {
                    final list = (v ?? '')
                        .split(RegExp(r'[,\s]+'))
                        .where((s) => s.trim().isNotEmpty);
                    if (list.isEmpty) return 'Isi minimal satu nomor';
                    if (list.any((s) => s.length > 10)) {
                      return 'Tiap nomor maks. 10 karakter';
                    }
                    return null;
                  },
                ),
              if (store.houseTypes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Tipe rumah',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Tanpa tipe'),
                      selected: _typeId == null,
                      onSelected: (_) => setState(() => _typeId = null),
                    ),
                    for (final t in store.sortedHouseTypes)
                      ChoiceChip(
                        label: Text(t.name),
                        selected: _typeId == t.id,
                        onSelected: (_) => setState(() => _typeId = t.id),
                      ),
                  ],
                ),
              ],
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
              Navigator.pop(context, (_numbers(), _typeId));
            }
          },
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}

class _MasterTile extends StatelessWidget {
  const _MasterTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.editLabel = 'Ubah nama',
  });

  final String editLabel;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(editLabel)),
            const PopupMenuItem(value: 'delete', child: Text('Hapus')),
          ],
        ),
      ),
    );
  }
}

String _countText({int? blocks, required Iterable<House> houses}) {
  final total = houses.length;
  final filled =
      houses.where((h) => store.residentOfHouse(h.id) != null).length;
  return [
    if (blocks != null) '$blocks blok',
    '$total rumah',
    '$filled terisi',
  ].join(' · ');
}

String? _requiredMax(String? v, int max) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return 'Wajib diisi';
  if (t.length > max) return 'Maks. $max karakter';
  return null;
}

Future<void> _confirmDelete(
    BuildContext context, String title, Future<void> Function() action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: const Text('Data yang dihapus tidak bisa dikembalikan.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await runAction(context, action(), success: 'Dihapus');
  }
}

/// Dialog satu isian teks. Mengembalikan teks (sudah di-trim) atau null.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String? initial,
  int maxLength = 60,
}) async {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (formKey.currentState!.validate()) {
          Navigator.pop(ctx, controller.text.trim());
        }
      }

      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: (v) => _requiredMax(v, maxLength),
            onFieldSubmitted: (_) => submit(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          FilledButton(onPressed: submit, child: const Text('Simpan')),
        ],
      );
    },
  );
  return result;
}

/// Hasil pilihan tipe: [typeId] null berarti "tanpa tipe".
typedef HouseTypeChoice = ({String? typeId});

/// Bottom sheet memilih tipe rumah. Mengembalikan null bila dibatalkan.
Future<HouseTypeChoice?> pickHouseType(
  BuildContext context, {
  required String title,
  String? selected,
}) {
  return showModalBottomSheet<HouseTypeChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Tanpa tipe'),
              selected: selected == null,
              onTap: () => Navigator.pop(ctx, (typeId: null)),
            ),
            for (final t in store.sortedHouseTypes)
              ListTile(
                leading: const Icon(Icons.straighten),
                title: Text(t.name),
                subtitle: t.areaText.isEmpty ? null : Text(t.areaText),
                selected: selected == t.id,
                onTap: () => Navigator.pop(ctx, (typeId: t.id)),
              ),
          ],
        ),
      ),
    ),
  );
}
