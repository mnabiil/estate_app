import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

Color billColor(BillStatus s) =>
    s == BillStatus.lunas ? Colors.green.shade600 : Colors.orange.shade700;

Color complaintColor(ComplaintStatus s) => switch (s) {
      ComplaintStatus.baru => Colors.blue.shade600,
      ComplaintStatus.diproses => Colors.orange.shade700,
      ComplaintStatus.selesai => Colors.green.shade600,
    };

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

class FilterBar<T> extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// Nilai `null` berarti "Semua".
  final Map<T?, String> options;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onChanged(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Menjalankan aksi async: tampilkan [success] bila berhasil, atau pesan error
/// bila gagal. Mengembalikan hasil aksi, atau `null` bila gagal.
Future<T?> runAction<T>(BuildContext context, Future<T> action,
    {String? success}) async {
  try {
    final result = await action;
    if (success != null && context.mounted) showSnack(context, success);
    return result;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Gagal: ${describeError(e)}');
    return null;
  }
}
