import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// Pilih rumah bertingkat: Cluster > Blok > No. rumah, dari master data.
/// Rumah yang sudah berpenghuni ditampilkan tapi tidak bisa dipilih.
class HousePickerField extends StatefulWidget {
  const HousePickerField({
    super.key,
    required this.houseId,
    required this.onChanged,
  });

  final String? houseId;
  final ValueChanged<String?> onChanged;

  @override
  State<HousePickerField> createState() => _HousePickerFieldState();
}

class _HousePickerFieldState extends State<HousePickerField> {
  String? _clusterId;
  String? _blockId;

  @override
  void initState() {
    super.initState();
    final h = widget.houseId == null ? null : store.houseById(widget.houseId!);
    _clusterId = h?.clusterId;
    _blockId = h?.blockId;
    // Satu cluster saja: langsung terpilih.
    final clusters = store.sortedClusters;
    if (_clusterId == null && clusters.length == 1) {
      _clusterId = clusters.first.id;
    }
  }

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

  Future<void> _pickCluster() async {
    final id = await _sheet<String>(
      'Pilih cluster',
      (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final c in store.sortedClusters)
            ListTile(
              leading: const Icon(Icons.holiday_village_outlined),
              title: Text(c.name),
              subtitle: Text('${_free(store.houses.where((h) => h.clusterId == c.id))} rumah kosong'),
              selected: c.id == _clusterId,
              onTap: () => Navigator.pop(ctx, c.id),
            ),
        ],
      ),
    );
    if (id == null || id == _clusterId) return;
    setState(() {
      _clusterId = id;
      _blockId = null;
    });
    widget.onChanged(null);
  }

  Future<void> _pickBlock() async {
    final id = await _sheet<String>(
      'Pilih blok',
      (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final b in store.blocksOf(_clusterId!))
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text('Blok ${b.name}'),
              subtitle: Text('${_free(store.housesOf(b.id))} rumah kosong'),
              selected: b.id == _blockId,
              onTap: () => Navigator.pop(ctx, b.id),
            ),
        ],
      ),
    );
    if (id == null || id == _blockId) return;
    setState(() => _blockId = id);
    widget.onChanged(null);
  }

  Future<void> _pickHouse() async {
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
              for (final h in store.housesOf(_blockId!))
                Builder(builder: (_) {
                  final r = store.residentOfHouse(h.id);
                  return Tooltip(
                    message: r == null ? 'Kosong' : 'Ditempati ${r.name}',
                    child: ChoiceChip(
                      avatar: r == null
                          ? null
                          : Icon(Icons.person, size: 16,
                              color: scheme.onSurfaceVariant),
                      label: Text(h.number),
                      selected: h.id == widget.houseId,
                      onSelected:
                          r == null ? (_) => Navigator.pop(ctx, h.id) : null,
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

  static int _free(Iterable<House> hs) =>
      hs.where((h) => store.residentOfHouse(h.id) == null).length;

  @override
  Widget build(BuildContext context) {
    if (store.houses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Belum ada data rumah. Tambahkan dulu di '
          'Akun → Master data perumahan.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final cluster = _clusterId == null ? null : store.clusterById(_clusterId!);
    final block = _blockId == null ? null : store.blockById(_blockId!);
    final house =
        widget.houseId == null ? null : store.houseById(widget.houseId!);

    return FormField<String>(
      validator: (_) => widget.houseId == null ? 'Pilih no. rumah' : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PickerBox(
            label: 'Cluster',
            value: cluster?.name,
            icon: Icons.holiday_village_outlined,
            onTap: _pickCluster,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PickerBox(
                  label: 'Blok',
                  value: block?.name,
                  icon: Icons.grid_view,
                  onTap: cluster == null ? null : _pickBlock,
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
      ),
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
