import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';
import 'payments_screen.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  BillStatus? _filter;

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

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
        final rid = store.currentUser!.residentId ?? '';
        var list =
            isAdmin ? store.bills.toList() : store.billsForResident(rid);
        if (_filter != null) {
          list = list.where((b) => b.status == _filter).toList();
        }
        list.sort((a, b) => b.period.compareTo(a.period));

        return Scaffold(
          appBar: AppBar(
            title: Text(isAdmin ? 'Tagihan IPL' : 'Tagihan Saya'),
            actions: [
              if (isAdmin && store.can(AdminPermission.bankAccounts))
                IconButton(
                  tooltip: 'Rekening pembayaran',
                  icon: const Icon(Icons.account_balance_outlined),
                  onPressed: () => _open(const BankAccountsScreen()),
                ),
              if (isAdmin && store.can(AdminPermission.billing)) ...[
                IconButton(
                  tooltip: 'Buat tagihan bulan ini',
                  icon: const Icon(Icons.post_add),
                  onPressed: _generate,
                ),
              ],
              IconButton(
                tooltip: isAdmin ? 'Pembayaran' : 'Riwayat pembayaran',
                icon: const Icon(Icons.history),
                onPressed: () => _open(const PaymentsScreen()),
              ),
            ],
          ),
          body: Column(
            children: [
              if (!isAdmin) ...[
                _UnpaidBanner(
                  total: store.unpaidTotal(rid),
                  onPay: () => startPaymentFlow(context),
                ),
                if (store.activePaymentOf(rid) case final p?)
                  _ActivePaymentCard(
                      payment: p,
                      onTap: () =>
                          _open(PaymentDetailScreen(paymentId: p.id))),
              ] else if (store.can(AdminPermission.billing) &&
                  store.paymentsToVerify.isNotEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(
                        '${store.paymentsToVerify.length} pembayaran perlu diverifikasi'),
                    subtitle: const Text('Cocokkan dengan mutasi rekening'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const PaymentsScreen()),
                  ),
                )
              else if (store.can(AdminPermission.bankAccounts) &&
                  store.bankAccounts.isEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: const Text('Rekening pembayaran belum diatur'),
                    subtitle: const Text('Warga belum bisa membayar IPL'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(const BankAccountsScreen()),
                  ),
                ),
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
                          final locked = !paid && store.isBillLocked(b);
                          return ListTile(
                            title: Text(isAdmin
                                ? '${r?.name} · ${r?.houseNo}'
                                : 'IPL ${formatMonth(b.period)}'),
                            subtitle: Text([
                              if (isAdmin) 'IPL ${formatMonth(b.period)}',
                              paid
                                  ? 'Dibayar ${formatDate(b.paidAt!)} · ${b.method}'
                                  : 'Jatuh tempo ${formatDate(b.dueDate)}'
                                      '${b.isOverdueOn(DateTime.now()) ? ' · terlambat' : ''}'
                                      '${locked ? ' · dalam pembayaran' : ''}',
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
                            onTap: b.paymentId != null
                                ? () => _open(
                                    PaymentDetailScreen(paymentId: b.paymentId!))
                                : paid || isAdmin
                                    ? null
                                    : () => startPaymentFlow(context,
                                        upToBillId: b.id),
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

class _ActivePaymentCard extends StatelessWidget {
  const _ActivePaymentCard({required this.payment, required this.onTap});
  final Payment payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = payment.statusOn(DateTime.now());
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text('Pembayaran ${formatRupiah(payment.total)}'),
        subtitle: Text(s == PaymentStatus.menungguTransfer
            ? 'Transfer sebelum ${formatDateTime(payment.expiresAt)}'
            : s.label),
        trailing: StatusChip(s.label, paymentColor(s)),
        onTap: onTap,
      ),
    );
  }
}

class _UnpaidBanner extends StatelessWidget {
  const _UnpaidBanner({required this.total, required this.onPay});
  final int total;
  final VoidCallback onPay;

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
            : Text(formatRupiah(total),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
        trailing: clear
            ? null
            : FilledButton(onPressed: onPay, child: const Text('Bayar')),
      ),
    );
  }
}
