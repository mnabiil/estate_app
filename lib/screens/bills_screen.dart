import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

const _paymentMethods = [
  (Icons.account_balance, 'Transfer Bank (Virtual Account)'),
  (Icons.qr_code_2, 'QRIS'),
  (Icons.account_balance_wallet_outlined, 'E-Wallet'),
];

class _BillsScreenState extends State<BillsScreen> {
  BillStatus? _filter;

  Future<void> _pay(Bill bill) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bayar IPL ${formatMonth(bill.period)}',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  Text(formatRupiah(bill.amount),
                      style: Theme.of(ctx).textTheme.headlineSmall),
                ],
              ),
            ),
            for (final (icon, name) in _paymentMethods)
              ListTile(
                leading: Icon(icon),
                title: Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, name),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    await runAction(
      context,
      store.payBill(bill.id, method),
      success: 'Pembayaran IPL ${formatMonth(bill.period)} berhasil (simulasi)',
    );
  }

  Future<void> _markPaid(Bill bill, Resident? r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai lunas?'),
        content: Text(
            'IPL ${formatMonth(bill.period)} untuk ${r?.name} (${r?.houseNo}) '
            'dibayar tunai ke pengelola.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tandai lunas')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runAction(context, store.payBill(bill.id, 'Tunai'),
        success: 'Tagihan ditandai lunas');
  }

  Future<void> _generate() async {
    final n = await runAction(context, store.generateBillsForCurrentMonth());
    if (n == null || !mounted) return;
    showSnack(
      context,
      n == 0
          ? 'Semua warga sudah punya tagihan bulan ini'
          : '$n tagihan baru dibuat untuk ${formatMonth(DateTime.now())}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final isAdmin = store.isAdmin;
        final rid = store.currentUser!.residentId;
        var list =
            isAdmin ? store.bills.toList() : store.billsForResident(rid!);
        if (_filter != null) {
          list = list.where((b) => b.status == _filter).toList();
        }
        list.sort((a, b) => b.period.compareTo(a.period));

        return Scaffold(
          appBar: AppBar(
            title: Text(isAdmin ? 'Tagihan IPL' : 'Tagihan Saya'),
            actions: [
              if (isAdmin)
                IconButton(
                  tooltip: 'Buat tagihan bulan ini',
                  icon: const Icon(Icons.post_add),
                  onPressed: _generate,
                ),
            ],
          ),
          body: Column(
            children: [
              if (!isAdmin) _UnpaidBanner(total: store.unpaidTotal(rid!)),
              FilterBar<BillStatus>(
                options: const {
                  null: 'Semua',
                  BillStatus.belumBayar: 'Belum bayar',
                  BillStatus.lunas: 'Lunas',
                },
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long, message: 'Tidak ada tagihan')
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final b = list[i];
                          final r = store.residentById(b.residentId);
                          final paid = b.status == BillStatus.lunas;
                          return ListTile(
                            title: Text(isAdmin
                                ? '${r?.name} · ${r?.houseNo}'
                                : 'IPL ${formatMonth(b.period)}'),
                            subtitle: Text([
                              if (isAdmin) 'IPL ${formatMonth(b.period)}',
                              paid
                                  ? 'Dibayar ${formatDate(b.paidAt!)} · ${b.method}'
                                  : 'Jatuh tempo ${formatDate(b.dueDate)}',
                            ].join('\n')),
                            isThreeLine: isAdmin,
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatRupiah(b.amount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                StatusChip(b.status.label, billColor(b.status)),
                              ],
                            ),
                            onTap: paid
                                ? null
                                : () => isAdmin ? _markPaid(b, r) : _pay(b),
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

class _UnpaidBanner extends StatelessWidget {
  const _UnpaidBanner({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clear = total == 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: clear ? scheme.secondaryContainer : scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(clear ? Icons.verified : Icons.info_outline),
        title: Text(clear ? 'Semua tagihan lunas' : 'Total belum dibayar'),
        subtitle: clear
            ? const Text('Terima kasih!')
            : const Text('Ketuk tagihan untuk membayar'),
        trailing: clear
            ? null
            : Text(formatRupiah(total),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
