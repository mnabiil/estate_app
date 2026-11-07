import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// Pilih rumah bertingkat dari master data:
/// Perumahan > Cluster > Tipe rumah > Blok > No. rumah.
///
/// Langkah yang pilihannya hanya satu terisi otomatis. Rumah yang sudah
/// berpenghuni ditampilkan tapi tidak bisa dipilih. Memilih perumahan lain
/// memindahkan perumahan aktif (warga baru masuk ke perumahan tersebut).
class HousePickerField extends StatefulWidget {
  const HousePickerField({
    super.key,
    required this.houseId,
    required this.onChanged,
    this.allowEstateChange = true,
    this.exceptResidentId,
  });

  final String? houseId;
  final ValueChanged<String?> onChanged;

  /// False untuk warga yang sudah ada: perumahan tidak bisa diganti.
  final bool allowEstateChange;

  /// Rumah yang ditempati warga ini tetap bisa dipilih (untuk pindah rumah).
  final String? exceptResidentId;

  @override
  State<HousePickerField> createState() => _HousePickerFieldState();
}

class _HousePickerFieldState extends State<HousePickerField> {
  String? _clusterId;
  String? _typeId;
  String? _blockId;

  @override
  void initState() {
    super.initState();
    final h = widget.houseId == null ? null : store.houseById(widget.houseId!);
    if (h != null) {
      _clusterId = h.clusterId;
      _blockId = h.blockId;
      _typeId = store.blockById(h.blockId)?.typeId ?? noTypeId;
    }
  }

  // ----- pilihan efektif (otomatis bila hanya ada satu) -----

  String? get _cluster {
    if (_clusterId != null && store.clusterById(_clusterId!) != null) {
      return _clusterId;
    }
    final all = store.clusters;
    return all.length == 1 ? all.first.id : null;
  }

  List<(String, String, String?)> _typeOptions(String clusterId) => [
        for (final t in store.typesOf(clusterId))
          (t.id, t.name, t.areaText.isEmpty ? null : t.areaText),
        if (store.blocksOf(clusterId, typeId: noTypeId).isNotEmpty)
          (noTypeId, 'Belum bertipe', null),
      ];

  String? get _type {
    final c = _cluster;
    if (c == null) return null;
    final opts = _typeOptions(c);
    if (_typeId != null && opts.any((o) => o.$1 == _typeId)) return _typeId;
    return opts.length == 1 ? opts.first.$1 : null;
  }

  String? get _block {
    final c = _cluster;
    final t = _type;
    if (c == null || t == null) return null;
    final list = store.blocksOf(c, typeId: t);
    if (_blockId != null && list.any((b) => b.id == _blockId)) return _blockId;
    return list.length == 1 ? list.first.id : null;
  }

  void _reset({bool cluster = false, bool type = false}) {
    if (cluster) _clusterId = null;
    if (type) _typeId = null;
    _blockId = null;
    widget.onChanged(null);
  }

  // ----- bottom sheet -----

  Future<T?> _sheet<T>(String title, Widget Function(BuildContext) body) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              Flexible(child: body(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickFromList(
    String title,
    IconData icon,
    String? selected,
    List<(String, String, String?)> options,
  ) =>
      _sheet<String>(
        title,
        (ctx) => ListView(
          shrinkWrap: true,
          children: [
            for (final (id, label, sub) in options)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                subtitle: sub == null ? null : Text(sub),
                selected: id == selected,
                onTap: () => Navigator.pop(ctx, id),
              ),
          ],
        ),
      );

  bool _isFree(House h) {
    final r = store.residentOfHouse(h.id);
    return r == null || r.id == widget.exceptResidentId;
  }

  int _free(Iterable<House> hs) => hs.where(_isFree).length;

  Future<void> _pickEstate() async {
    final id = await _pickFromList(
      'Pilih perumahan',
      Icons.location_city_outlined,
      store.activeEstateId,
      [for (final e in store.estates) (e.id, e.name, null)],
    );
    if (id == null || id == store.activeEstateId || !mounted) return;
    setState(() => _reset(cluster: true, type: true));
    await runAction(context, store.switchEstate(id));
  }

  Future<void> _pickCluster() async {
    final id = await _pickFromList(
      'Pilih cluster',
      Icons.holiday_village_outlined,
      _cluster,
      [
        for (final c in store.sortedClusters)
          (
            c.id,
            c.name,
            '${_free(store.houses.where((h) => h.clusterId == c.id))} rumah kosong',
          ),
      ],
    );
    if (id == null || id == _cluster) return;
    setState(() {
      _reset(type: true);
      _clusterId = id;
    });
  }

  Future<void> _pickType() async {
    final c = _cluster!;
    final id = await _pickFromList(
      'Pilih tipe rumah',
      Icons.straighten,
      _type,
      [
        for (final (id, label, area) in _typeOptions(c))
          (
            id,
            label,
            [
              if (area != null) area,
              '${_free(store.blocksOf(c, typeId: id).expand((b) => store.housesOf(b.id)))} rumah kosong',
            ].join(' · '),
          ),
      ],
    );
    if (id == null || id == _type) return;
    setState(() {
      _reset();
      _typeId = id;
    });
  }

  Future<void> _pickBlock() async {
    final id = await _pickFromList(
      'Pilih blok',
      Icons.grid_view,
      _block,
      [
        for (final b in store.blocksOf(_cluster!, typeId: _type))
          (b.id, 'Blok ${b.name}', '${_free(store.housesOf(b.id))} rumah kosong'),
      ],
    );
    if (id == null || id == _block) return;
    setState(() {
      _reset();
      _blockId = id;
    });
  }

  Future<void> _pickHouse() async {
    final blockId = _block!;
    final id = await _sheet<String>(
      'Pilih no. rumah',
      (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in store.housesOf(blockId))
                Builder(builder: (_) {
                  final r = store.residentOfHouse(h.id);
                  final free = _isFree(h);
                  return Tooltip(
                    message: r == null ? 'Kosong' : 'Ditempati ${r.name}',
                    child: ChoiceChip(
                      avatar: r == null
                          ? null
                          : Icon(Icons.person,
                              size: 16, color: scheme.onSurfaceVariant),
                      label: Text(h.number),
                      selected: h.id == widget.houseId,
                      onSelected:
                          free ? (_) => Navigator.pop(ctx, h.id) : null,
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
    if (id != null) widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final clusterId = _cluster;
        final typeId = _type;
        final blockId = _block;
        final cluster = clusterId == null ? null : store.clusterById(clusterId);
        final type = typeId == null || typeId == noTypeId
            ? null
            : store.houseTypeById(typeId);
        final block = blockId == null ? null : store.blockById(blockId);
        final house =
            widget.houseId == null ? null : store.houseById(widget.houseId!);

        return FormField<String>(
          validator: (_) => widget.houseId == null ? 'Pilih no. rumah' : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PickerBox(
                label: 'Perumahan',
                value: store.estateName,
                icon: Icons.location_city_outlined,
                onTap: widget.allowEstateChange ? _pickEstate : null,
              ),
              const SizedBox(height: 10),
              if (store.houses.isEmpty)
                Text(
                  'Perumahan ini belum punya data rumah. Tambahkan dulu di '
                  'Akun → Master data.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else ...[
                _PickerBox(
                  label: 'Cluster',
                  value: cluster?.name,
                  icon: Icons.holiday_village_outlined,
                  onTap: _pickCluster,
                ),
                const SizedBox(height: 10),
                _PickerBox(
                  label: 'Tipe rumah',
                  value: typeId == noTypeId
                      ? 'Belum bertipe'
                      : type == null
                          ? null
                          : [type.name, if (type.areaText.isNotEmpty) type.areaText]
                              .join(' · '),
                  icon: Icons.straighten,
                  onTap: cluster == null ? null : _pickType,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PickerBox(
                        label: 'Blok',
                        value: block?.name,
                        icon: Icons.grid_view,
                        onTap: typeId == null ? null : _pickBlock,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PickerBox(
                        label: 'No. rumah',
                        value: house?.number,
                        icon: Icons.home_outlined,
                        onTap: block == null ? null : _pickHouse,
                        errorText: state.errorText,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PickerBox extends StatelessWidget {
  const _PickerBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.errorText,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          enabled: onTap != null,
          errorText: errorText,
        ),
        child: Text(value ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
