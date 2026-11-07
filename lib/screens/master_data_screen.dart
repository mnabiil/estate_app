import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets.dart';

/// Master data (khusus pengelola), mengikuti alur:
/// Perumahan > Cluster > Tipe rumah > Blok > No. rumah.
///
/// Data ini menjadi daftar pilihan saat menambah warga, jadi nomor rumah
/// tidak perlu diketik manual.
class MasterDataScreen extends StatelessWidget {
  const MasterDataScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final clusters = store.sortedClusters;
        final occupied = store.residents.where((r) => r.houseId != null).length;

        return Scaffold(
          appBar: AppBar(title: const Text('Master Data')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editCluster(context),
            icon: const Icon(Icons.add),
            label: const Text('Cluster'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const _StepHint(),
              const SizedBox(height: 16),
              _SectionHeader(
                step: 1,
                title: 'Perumahan',
                action: TextButton.icon(
                  onPressed: () => editEstate(context, create: true),
                  icon: const Icon(Icons.add),
                  label: const Text('Perumahan'),
                ),
              ),
              for (final e in store.estates)
                if (e.id == store.activeEstateId)
                  Card(
                    color: scheme.primary,
                    child: ListTile(
                      iconColor: scheme.onPrimary,
                      textColor: scheme.onPrimary,
                      leading: const Icon(Icons.location_city),
                      title: Text(store.estateName,
                          style: TextStyle(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [
                          if (store.estateAddress.isNotEmpty)
                            store.estateAddress,
                          'IPL ${formatRupiah(store.fee)}/bulan · '
                              '${store.houses.length} rumah, $occupied terisi',
                        ].join('\n'),
                        style: TextStyle(
                            color: scheme.onPrimary.withValues(alpha: 0.85)),
                      ),
                      isThreeLine: store.estateAddress.isNotEmpty,
                      trailing: IconButton(
                        tooltip: 'Ubah profil perumahan',
                        color: scheme.onPrimary,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => editEstate(context),
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.location_city_outlined),
                      title: Text(e.name),
                      subtitle: const Text('Ketuk untuk beralih'),
                      trailing: const Icon(Icons.swap_horiz),
                      onTap: () => runAction(
                        context,
                        store.switchEstate(e.id),
                        success: 'Beralih ke ${e.name}',
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              _SectionHeader(
                step: 2,
                title: 'Cluster di ${store.estateName}',
              ),
              if (clusters.isEmpty)
                const EmptyState(
                  icon: Icons.holiday_village_outlined,
                  message: 'Belum ada cluster di perumahan ini.',
                ),
              for (final c in clusters)
                _MasterTile(
                  icon: Icons.holiday_village_outlined,
                  title: c.name,
                  subtitle: [
                    '${store.typesOf(c.id).length} tipe',
                    _countText(
                      blocks: store.blocksOf(c.id).length,
                      houses: store.houses.where((h) => h.clusterId == c.id),
                    ),
                  ].join(' · '),
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

/// Isi cluster: tipe rumah (langkah 3) lalu blok per tipe (langkah 4).
class ClusterScreen extends StatelessWidget {
  const ClusterScreen({super.key, required this.clusterId});

  final String clusterId;

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
        clusterId,
        n,
        id: t?.id,
        buildingArea: int.tryParse(lb.text.trim()),
        landArea: int.tryParse(lt.text.trim()),
      ),
      success: t == null ? '$n ditambahkan' : 'Tipe disimpan',
    );
  }

  Future<void> _editBlock(BuildContext context,
      {HouseBlock? block, String? typeId}) async {
    if (store.typesOf(clusterId).isEmpty) {
      showSnack(context, 'Tambahkan tipe rumah dulu, lalu bloknya.');
      return;
    }
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _BlockDialog(
        clusterId: clusterId,
        block: block,
        initialTypeId: block?.typeId ?? typeId,
      ),
    );
    if (result == null || !context.mounted) return;
    final (name, chosenType) = result;
    await runAction(
      context,
      store.saveBlock(clusterId, name, id: block?.id, typeId: chosenType),
      success: block == null ? 'Blok $name ditambahkan' : 'Blok disimpan',
    );
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
        final theme = Theme.of(context);
        final types = store.typesOf(clusterId);
        final untyped = store.blocksOf(clusterId, typeId: noTypeId);

        Widget blockTile(HouseBlock b) => _MasterTile(
              icon: Icons.grid_view,
              title: 'Blok ${b.name}',
              subtitle: _countText(houses: store.housesOf(b.id)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BlockScreen(blockId: b.id))),
              editLabel: 'Ubah',
              onEdit: () => _editBlock(context, block: b),
              onDelete: () => _confirmDelete(
                context,
                'Hapus blok ${b.name}?',
                () => store.deleteBlock(b.id),
              ),
            );

        return Scaffold(
          appBar: AppBar(title: Text(cluster.name)),
          floatingActionButton: types.isEmpty
              ? FloatingActionButton.extended(
                  onPressed: () => _editType(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Tipe rumah'),
                )
              : FloatingActionButton.extended(
                  onPressed: () => _editBlock(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Blok'),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(store.estateName,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              _SectionHeader(
                step: 3,
                title: 'Tipe rumah',
                action: TextButton.icon(
                  onPressed: () => _editType(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Tipe'),
                ),
              ),
              if (types.isEmpty)
                const EmptyState(
                  icon: Icons.straighten,
                  message: 'Belum ada tipe rumah di cluster ini.\n'
                      'Contoh: Tipe 36/72 (LB 36 m², LT 72 m²).',
                ),
              for (final t in types)
                _MasterTile(
                  icon: Icons.straighten,
                  title: t.name,
                  subtitle: [
                    if (t.areaText.isNotEmpty) t.areaText,
                    '${store.blocksOf(clusterId, typeId: t.id).length} blok',
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
              if (types.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SectionHeader(step: 4, title: 'Blok per tipe'),
                for (final t in types) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(t.name,
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: theme.colorScheme.primary)),
                        ),
                        TextButton(
                          onPressed: () => _editBlock(context, typeId: t.id),
                          child: const Text('+ Blok'),
                        ),
                      ],
                    ),
                  ),
                  if (store.blocksOf(clusterId, typeId: t.id).isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      child: Text('Belum ada blok bertipe ini.',
                          style: theme.textTheme.bodySmall),
                    ),
                  for (final b in store.blocksOf(clusterId, typeId: t.id))
                    blockTile(b),
                ],
              ],
              if (untyped.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text('Belum bertipe (data lama) — ketuk ⋮ › Ubah',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
                for (final b in untyped) blockTile(b),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Isi blok: nomor rumah (langkah 5). Tipe mengikuti blok.
class BlockScreen extends StatelessWidget {
  const BlockScreen({super.key, required this.blockId});

  final String blockId;

  Future<void> _addHouses(BuildContext context) async {
    final numbers = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _AddHousesDialog(),
    );
    if (numbers == null || numbers.isEmpty || !context.mounted) return;
    final added = await runAction(context, store.addHouses(blockId, numbers));
    if (added == null || !context.mounted) return;
    final skipped = numbers.length - added;
    showSnack(
      context,
      '$added nomor rumah ditambahkan'
      '${skipped > 0 ? ' ($skipped sudah ada, dilewati)' : ''}',
    );
  }

  void _showHouse(BuildContext context, House h) {
    final r = store.residentOfHouse(h.id);
    final type = store.houseTypeOf(h);
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
              Text([
                store.estateName,
                store.clusterById(h.clusterId)?.name ?? '',
                if (type != null) type.name,
              ].join(' · ')),
              if (type?.areaText.isNotEmpty == true) Text(type!.areaText),
              const SizedBox(height: 16),
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
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final type = store.houseTypeById(block.typeId);
        final houses = store.housesOf(blockId);
        return Scaffold(
          appBar: AppBar(title: Text('Blok ${block.name}')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addHouses(context),
            icon: const Icon(Icons.add),
            label: const Text('No. rumah'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  [
                    store.clusterById(block.clusterId)?.name ?? '',
                    type == null
                        ? 'belum bertipe'
                        : [type.name, if (type.areaText.isNotEmpty) type.areaText]
                            .join(' · '),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: houses.isEmpty
                    ? const EmptyState(
                        icon: Icons.home_outlined,
                        message: 'Belum ada nomor rumah.\n'
                            'Tambahkan sekaligus, mis. nomor 1 sampai 20.',
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 110,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.95,
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
                                          ? AppColors.lime
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
                                    Text(
                                      r?.name.split(' ').first ?? 'Kosong',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: filled
                                            ? scheme.onPrimary
                                                .withValues(alpha: 0.85)
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
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog & komponen bersama
// ---------------------------------------------------------------------------

/// Dialog profil perumahan. [create] = tambah perumahan baru (lalu beralih
/// ke sana); selain itu mengubah perumahan yang sedang aktif.
Future<void> editEstate(BuildContext context, {bool create = false}) async {
  final name = TextEditingController(text: create ? '' : store.estateName);
  final address =
      TextEditingController(text: create ? '' : store.estateAddress);
  final fee = TextEditingController(text: create ? '$monthlyFee' : '${store.fee}');
  final formKey = GlobalKey<FormState>();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(create ? 'Tambah perumahan' : 'Profil perumahan'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: create,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama perumahan',
                  hintText: 'Contoh: Nilaya Residence',
                ),
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
          child: Text(create ? 'Tambah' : 'Simpan'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final n = name.text.trim();
  final a = address.text.trim();
  final f = int.parse(fee.text.replaceAll('.', ''));
  await runAction(
    context,
    create
        ? store.createEstate(name: n, address: a, fee: f)
        : store.updateEstate(name: n, address: a, fee: f),
    success: create ? '$n ditambahkan & aktif' : 'Profil perumahan disimpan',
  );
}

/// Bottom sheet memilih perumahan aktif (pengelola dengan >1 perumahan).
Future<void> showEstateSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Pilih perumahan',
                style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final e in store.estates)
            ListTile(
              leading: const Icon(Icons.location_city_outlined),
              title: Text(e.name),
              selected: e.id == store.activeEstateId,
              trailing: e.id == store.activeEstateId
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                runAction(context, store.switchEstate(e.id));
              },
            ),
        ],
      ),
    ),
  );
}

class _StepHint extends StatelessWidget {
  const _StepHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = ['Perumahan', 'Cluster', 'Tipe rumah', 'Blok', 'No. rumah'];
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Icon(Icons.chevron_right,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
          Text('${i + 1}. ${steps[i]}',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.step, required this.title, this.action});

  final int step;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.lime,
            foregroundColor: Colors.white,
            child: Text('$step',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Dialog blok: nama + tipe (wajib, dari cluster yang sama).
class _BlockDialog extends StatefulWidget {
  const _BlockDialog({
    required this.clusterId,
    this.block,
    this.initialTypeId,
  });

  final String clusterId;
  final HouseBlock? block;
  final String? initialTypeId;

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.block?.name);
  late String? _typeId = widget.initialTypeId ??
      (store.typesOf(widget.clusterId).length == 1
          ? store.typesOf(widget.clusterId).first.id
          : null);
  bool _showTypeError = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.block == null ? 'Tambah blok' : 'Ubah blok'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: widget.block == null,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nama blok',
                  hintText: 'Contoh: A1',
                ),
                validator: (v) => _requiredMax(v, 20),
              ),
              const SizedBox(height: 16),
              Text('Tipe rumah di blok ini', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in store.typesOf(widget.clusterId))
                    ChoiceChip(
                      label: Text(t.name),
                      selected: _typeId == t.id,
                      onSelected: (_) => setState(() {
                        _typeId = t.id;
                        _showTypeError = false;
                      }),
                    ),
                ],
              ),
              if (_showTypeError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Pilih tipe rumah',
                      style: TextStyle(color: theme.colorScheme.error)),
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
            final okName = _formKey.currentState!.validate();
            setState(() => _showTypeError = _typeId == null);
            if (okName && _typeId != null) {
              Navigator.pop(context, (_name.text.trim(), _typeId!));
            }
          },
          child: const Text('Simpan'),
        ),
      ],
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

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _manual.dispose();
    super.dispose();
  }

  String? _int(String? v) =>
      int.tryParse(v ?? '') == null ? 'Isi angka' : null;

  List<String> _split(String text) => text
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  List<String> _numbers() {
    if (!_range) return _split(_manual.text);
    final a = int.parse(_from.text);
    final b = int.parse(_to.text);
    return [
      for (var n = a; n <= b; n++) _pad ? n.toString().padLeft(2, '0') : '$n',
    ];
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
                    final list = _split(v ?? '');
                    if (list.isEmpty) return 'Isi minimal satu nomor';
                    if (list.any((s) => s.length > 10)) {
                      return 'Tiap nomor maks. 10 karakter';
                    }
                    return null;
                  },
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
              Navigator.pop(context, _numbers());
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

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String editLabel;

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
  return showDialog<String>(
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
}
