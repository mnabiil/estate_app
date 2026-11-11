import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../photo_widgets.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

Color paymentColor(PaymentStatus s) => switch (s) {
      PaymentStatus.menungguTransfer => Colors.blue.shade600,
      PaymentStatus.menungguVerifikasi => Colors.orange.shade700,
      PaymentStatus.ditolak => Colors.red.shade600,
      PaymentStatus.diterima => Colors.green.shade600,
      PaymentStatus.dibatalkan || PaymentStatus.kedaluwarsa =>
        Colors.grey.shade600,
    };

String formatDateTime(DateTime d) => '${formatDate(d)} ${formatTime(d)}';

/// "2026-09" → "Sep 2026".
String periodLabel(String key) {
  try {
    return formatMonth(parseKey(key));
  } catch (_) {
    return key;
  }
}

void _copy(BuildContext context, String text, String what) {
  Clipboard.setData(ClipboardData(text: text));
  showSnack(context, '$what disalin');
}

/// Warga memilih tagihan yang mau dibayar sekaligus. Tagihan terlama
/// selalu ikut: mencentang tagihan baru otomatis mencentang yang lebih lama.
/// Mengembalikan pembayaran yang dibuat, atau null bila batal.
Future<Payment?> startPaymentFlow(BuildContext context, {String? upToBillId}) async {
  final rid = store.currentUser?.residentId;
  if (rid == null) return null;
  final active = store.activePaymentOf(rid);
  if (active != null) {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PaymentDetailScreen(paymentId: active.id)));
    return null;
  }
  if (store.bankAccounts.isEmpty) {
    showSnack(context, 'Rekening pembayaran belum diatur pengelola.');
    return null;
  }
  final unpaid = store.unpaidBillsOf(rid);
  if (unpaid.isEmpty) {
    showSnack(context, 'Semua tagihan sudah lunas');
    return null;
  }
  final start = upToBillId == null
      ? unpaid.length
      : unpaid.indexWhere((b) => b.id == upToBillId) + 1;
  final selected = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SelectBillsSheet(
        bills: unpaid, initialCount: start <= 0 ? unpaid.length : start),
  );
  if (selected == null || selected.isEmpty || !context.mounted) return null;
  final chosen = unpaid.where((b) => selected.contains(b.id)).toList();
  final ok = await confirmSave(context,
      title: 'Bayar ${chosen.length} tagihan?',
      details: {
        'Tagihan': chosen.map((b) => formatMonth(b.period)).join(', '),
        'Jumlah': formatRupiah(chosen.fold(0, (t, b) => t + b.amount)),
      },
      note: 'Kode unik 3 digit akan ditambahkan ke total. Transfer dalam '
          '24 jam setelah kode dibuat.',
      action: 'Ya, buat kode bayar');
  if (!ok || !context.mounted) return null;
  final p = await runAction(context, store.createPayment(selected));
  if (p == null || !context.mounted) return null;
  await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentDetailScreen(paymentId: p.id)));
  return p;
}

class _SelectBillsSheet extends StatefulWidget {
  const _SelectBillsSheet({required this.bills, required this.initialCount});
  final List<Bill> bills;
  final int initialCount;

  @override
  State<_SelectBillsSheet> createState() => _SelectBillsSheetState();
}

class _SelectBillsSheetState extends State<_SelectBillsSheet> {
  late int _count = widget.initialCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = widget.bills.take(_count).toList();
    final total = chosen.fold<int>(0, (t, b) => t + b.amount);
    final now = DateTime.now();
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Pilih tagihan yang dibayar',
                  style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Beberapa tagihan bisa dibayar sekaligus dalam satu transfer. '
                'Tagihan terlama wajib ikut dibayar lebih dulu.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < widget.bills.length; i++)
                    CheckboxListTile(
                      value: i < _count,
                      onChanged: (v) =>
                          setState(() => _count = v == true ? i + 1 : i),
                      title: Text('IPL ${formatMonth(widget.bills[i].period)}'),
                      subtitle: Text(
                          'Jatuh tempo ${formatDate(widget.bills[i].dueDate)}'
                          '${widget.bills[i].isOverdueOn(now) ? ' · terlambat' : ''}'),
                      secondary: Text(formatRupiah(widget.bills[i].amount)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_count tagihan', style: theme.textTheme.bodySmall),
                        Text(formatRupiah(total),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('+ kode unik', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _count == 0
                        ? null
                        : () => Navigator.pop(
                            context, [for (final b in chosen) b.id]),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Buat kode bayar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail pembayaran: instruksi transfer (warga) atau verifikasi (pengelola).
class PaymentDetailScreen extends StatelessWidget {
  const PaymentDetailScreen({super.key, required this.paymentId});
  final String paymentId;

  Future<void> _upload(BuildContext context, Payment p) async {
    final photo = await pickPhoto(context);
    if (photo == null || !context.mounted) return;
    final ok = await confirmSave(context,
        title: 'Kirim bukti transfer?',
        details: {
          'Total transfer': formatRupiah(p.total),
          'Berita': p.reference,
          'Tagihan': p.periods.map(periodLabel).join(', '),
        },
        note: 'Pastikan nominal di bukti sama persis, termasuk 3 digit kode '
            'unik.',
        action: 'Ya, kirim');
    if (!ok || !context.mounted) return;
    await runAction(context, store.submitPaymentProof(p.id, photo),
        success: 'Bukti terkirim. Menunggu verifikasi pengelola.');
  }

  Future<void> _cancel(BuildContext context, Payment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan pembayaran?'),
        content: const Text('Kode unik ini tidak berlaku lagi. Jangan transfer '
            'dengan kode ini setelah dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Batalkan')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, store.cancelPayment(p.id),
        success: 'Pembayaran dibatalkan');
  }

  Future<void> _verify(BuildContext context, Payment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terima pembayaran?'),
        content: Text('Pastikan dana ${formatRupiah(p.total)} sudah masuk ke '
            'rekening perumahan. ${p.billIds.length} tagihan akan ditandai '
            'lunas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Terima')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context, store.verifyPayment(p.id),
        success: 'Pembayaran diterima, tagihan lunas');
  }

  Future<void> _reject(BuildContext context, Payment p) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak bukti transfer'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Alasan',
              hintText: 'mis. Dana belum masuk / nominal tidak sesuai'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Tolak')),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    await runAction(context, store.rejectPayment(p.id, reason),
        success: 'Bukti ditolak, warga diminta unggah ulang');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.paymentById(paymentId);
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Pembayaran')),
            body: const EmptyState(
                icon: Icons.receipt_long, message: 'Pembayaran tidak ditemukan'),
          );
        }
        final theme = Theme.of(context);
        final now = DateTime.now();
        final status = p.statusOn(now);
        final mine = !store.isAdmin && store.currentUser?.residentId == p.residentId;
        final canReview = store.isAdmin &&
            store.can(AdminPermission.billing) &&
            p.status == PaymentStatus.menungguVerifikasi;
        final showInstructions = mine &&
            (status == PaymentStatus.menungguTransfer ||
                status == PaymentStatus.ditolak);
        final code = p.uniqueCode.toString().padLeft(3, '0');
        final totalText = formatRupiah(p.total);
        final proof = p.proofUrl;

        return Scaffold(
          appBar: AppBar(title: Text('Pembayaran ${p.houseNo}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  StatusChip(status.label, paymentColor(status)),
                  const Spacer(),
                  Text(formatDateTime(p.createdAt),
                      style: theme.textTheme.bodySmall),
                ],
              ),
              if (p.note.isNotEmpty && p.status == PaymentStatus.ditolak) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Bukti ditolak pengelola'),
                    subtitle: Text(p.note),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total transfer', style: theme.textTheme.bodySmall),
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: totalText.substring(
                                        0, totalText.length - 3)),
                                TextSpan(
                                  text: totalText
                                      .substring(totalText.length - 3),
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ]),
                              key: const Key('payment-total'),
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Salin nominal',
                            icon: const Icon(Icons.copy),
                            onPressed: () =>
                                _copy(context, '${p.total}', 'Nominal'),
                          ),
                        ],
                      ),
                      if (showInstructions)
                        Text(
                          'Transfer TEPAT sampai 3 digit terakhir ($code) agar '
                          'pembayaran mudah dikenali.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      const Divider(height: 24),
                      _row(context, 'Tagihan',
                          p.periods.map(periodLabel).join(', ')),
                      _row(context, 'Jumlah tagihan', formatRupiah(p.baseAmount)),
                      _row(context, 'Kode unik', '+$code'),
                      Row(
                        children: [
                          Expanded(
                              child: _row(context, 'Berita transfer', p.reference)),
                          IconButton(
                            tooltip: 'Salin berita',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () =>
                                _copy(context, p.reference, 'Berita transfer'),
                          ),
                        ],
                      ),
                      if (store.isAdmin)
                        _row(context, 'Warga', '${p.residentName} · ${p.houseNo}'),
                      if (status == PaymentStatus.menungguTransfer)
                        _row(context, 'Bayar sebelum',
                            formatDateTime(p.expiresAt)),
                      if (p.submittedAt != null)
                        _row(context, 'Bukti dikirim',
                            formatDateTime(p.submittedAt!)),
                      if (p.reviewedAt != null)
                        _row(
                            context,
                            p.status == PaymentStatus.diterima
                                ? 'Diverifikasi'
                                : 'Diperiksa',
                            '${formatDateTime(p.reviewedAt!)}'
                                '${p.reviewedBy.isNotEmpty ? ' · ${p.reviewedBy}' : ''}'),
                    ],
                  ),
                ),
              ),
              if (showInstructions) ...[
                const SizedBox(height: 12),
                Text('Transfer ke salah satu rekening',
                    style: theme.textTheme.titleSmall),
                for (final a in store.bankAccounts)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance),
                      title: Text('${a.bankName} · ${a.accountNumber}'),
                      subtitle: Text([
                        'a.n. ${a.accountName}',
                        if (a.title.isNotEmpty) a.title,
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Salin nomor rekening',
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copy(
                            context,
                            a.accountNumber.replaceAll(RegExp(r'[^0-9]'), ''),
                            'Nomor rekening'),
                      ),
                    ),
                  ),
              ],
              if (proof != null && proof.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Bukti transfer', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PhotoThumb(
                    source: proof,
                    size: 120,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PhotoViewer(photos: [proof]))),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (mine && p.canUploadProofOn(now))
                FilledButton.icon(
                  onPressed: () => _upload(context, p),
                  icon: const Icon(Icons.upload),
                  label: Text(p.status == PaymentStatus.ditolak
                      ? 'Unggah ulang bukti transfer'
                      : 'Saya sudah transfer · unggah bukti'),
                ),
              if (mine &&
                  (p.status == PaymentStatus.menungguTransfer ||
                      p.status == PaymentStatus.ditolak) &&
                  status != PaymentStatus.kedaluwarsa)
                TextButton(
                  onPressed: () => _cancel(context, p),
                  child: const Text('Batalkan pembayaran'),
                ),
              if (mine && status == PaymentStatus.menungguVerifikasi)
                const Text(
                    'Bukti sudah dikirim. Tagihan akan lunas setelah pengelola '
                    'memverifikasi dana masuk.',
                    textAlign: TextAlign.center),
              if (mine && status == PaymentStatus.kedaluwarsa)
                const Text(
                    'Batas waktu transfer lewat. Buat kode pembayaran baru dari '
                    'halaman Tagihan. Bila sudah terlanjur transfer, hubungi '
                    'pengelola.',
                    textAlign: TextAlign.center),
              if (canReview)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _reject(context, p),
                        icon: const Icon(Icons.close),
                        label: const Text('Tolak'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _verify(context, p),
                        icon: const Icon(Icons.check),
                        label: const Text('Terima'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

/// Daftar pembayaran. Pengelola: semua (default: menunggu verifikasi).
/// Warga: riwayat pembayaran rumahnya.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late PaymentStatus? _filter =
      store.isAdmin ? PaymentStatus.menungguVerifikasi : null;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final rid = store.currentUser?.residentId;
        var list = store.isAdmin
            ? store.payments.toList()
            : store.payments.where((p) => p.residentId == rid).toList();
        if (_filter != null) {
          list = list.where((p) => p.statusOn(now) == _filter).toList();
        }
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Scaffold(
          appBar: AppBar(
              title: Text(store.isAdmin
                  ? 'Verifikasi pembayaran'
                  : 'Riwayat pembayaran')),
          body: Column(
            children: [
              FilterBar<PaymentStatus>(
                options: {
                  null: 'Semua',
                  PaymentStatus.menungguVerifikasi: 'Perlu verifikasi',
                  PaymentStatus.menungguTransfer: 'Menunggu transfer',
                  PaymentStatus.ditolak: 'Ditolak',
                  PaymentStatus.diterima: 'Diterima',
                },
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: store.refresh,
                  child: list.isEmpty
                    ? const EmptyState(
                        scrollable: true,
                        icon: Icons.payments_outlined,
                        message: 'Tidak ada pembayaran')
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = list[i];
                          final s = p.statusOn(now);
                          return ListTile(
                            title: Text(store.isAdmin
                                ? '${p.residentName} · ${p.houseNo}'
                                : p.periods.map(periodLabel).join(', ')),
                            subtitle: Text([
                              if (store.isAdmin)
                                p.periods.map(periodLabel).join(', '),
                              '${p.reference} · ${formatDateTime(p.submittedAt ?? p.createdAt)}',
                            ].join('\n')),
                            isThreeLine: store.isAdmin,
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatRupiah(p.total),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                StatusChip(s.label, paymentColor(s)),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PaymentDetailScreen(paymentId: p.id))),
                          );
                        },
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pengelola (hak tagihan): rekening tujuan transfer perumahan. Rekening
/// baru bisa sekaligus ditambahkan ke beberapa perumahan.
class BankAccountsScreen extends StatelessWidget {
  const BankAccountsScreen({super.key});

  Future<void> _edit(BuildContext context, [int? index]) async {
    final old = index == null ? null : store.bankAccounts[index];
    final result = await showDialog<(BankAccount, Set<String>)>(
      context: context,
      builder: (_) => _BankAccountDialog(old: old),
    );
    if (result == null || !context.mounted) return;
    final (account, estates) = result;
    final confirmed = await confirmSave(context,
        title: index == null ? 'Tambah rekening?' : 'Simpan perubahan rekening?',
        details: {
          'Nama rekening': account.title,
          'Bank': account.bankName,
          'No. rekening': account.accountNumber,
          'Atas nama': account.accountName,
          if (index == null)
            'Perumahan':
                [for (final id in estates) store.estateNameOf(id)].join(', '),
        },
        note: 'Pastikan nomor rekening benar: warga akan mentransfer ke '
            'rekening ini.');
    if (!confirmed || !context.mounted) return;
    if (index == null) {
      await runAction(context, store.addBankAccount(account, estates.toList()),
          success: estates.length > 1
              ? 'Rekening ditambahkan ke ${estates.length} perumahan'
              : 'Rekening ditambahkan');
    } else {
      final list = store.bankAccounts.toList()..[index] = account;
      await runAction(context, store.saveBankAccounts(list),
          success: 'Rekening diperbarui');
    }
  }

  Future<void> _delete(BuildContext context, int index) async {
    final a = store.bankAccounts[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus rekening?'),
        content: Text('${a.bankName} ${a.accountNumber} tidak lagi tampil '
            'sebagai tujuan transfer di $estateName.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final list = store.bankAccounts.toList()..removeAt(index);
    await runAction(context, store.saveBankAccounts(list),
        success: 'Rekening dihapus');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final accounts = store.bankAccounts;
        return Scaffold(
          appBar: AppBar(title: const Text('Rekening pembayaran')),
          floatingActionButton: accounts.length >= 5
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Rekening'),
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                    'Rekening $estateName. Warga membayar IPL hanya lewat '
                    'transfer ke rekening berikut. Setiap pembayaran diberi '
                    'kode unik 3 digit sehingga transfer tiap rumah mudah '
                    'dikenali di mutasi rekening.'),
              ),
              if (accounts.isEmpty)
                const EmptyState(
                    icon: Icons.account_balance,
                    message: 'Belum ada rekening. Warga belum bisa membayar.'),
              for (var i = 0; i < accounts.length; i++)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: ListTile(
                    leading: const Icon(Icons.account_balance),
                    title: Text(accounts[i].title.isNotEmpty
                        ? accounts[i].title
                        : accounts[i].bankName),
                    subtitle: Text([
                      if (accounts[i].title.isNotEmpty) accounts[i].bankName,
                      accounts[i].accountNumber,
                      'a.n. ${accounts[i].accountName}',
                    ].join(' · ')),
                    onTap: () => _edit(context, i),
                    trailing: IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, i),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BankAccountDialog extends StatefulWidget {
  const _BankAccountDialog({this.old});
  final BankAccount? old;

  @override
  State<_BankAccountDialog> createState() => _BankAccountDialogState();
}

class _BankAccountDialogState extends State<_BankAccountDialog> {
  late final _title = TextEditingController(text: widget.old?.title);
  late final _bank = TextEditingController(text: widget.old?.bankName);
  late final _number = TextEditingController(text: widget.old?.accountNumber);
  late final _name =
      TextEditingController(text: widget.old?.accountName ?? estateName);
  Set<String> _estates = {
    if (store.activeEstateId != null) store.activeEstateId!
  };

  @override
  void dispose() {
    _title.dispose();
    _bank.dispose();
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.old == null;
    return AlertDialog(
      title: Text(adding ? 'Tambah rekening' : 'Ubah rekening'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: _title,
                maxLength: 60,
                decoration: const InputDecoration(
                    labelText: 'Nama rekening (opsional)',
                    hintText: 'mis. Rekening IPL Cluster A')),
            TextField(
                controller: _bank,
                decoration: const InputDecoration(
                    labelText: 'Nama bank', hintText: 'mis. BCA')),
            TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nomor rekening')),
            TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Nama pemilik rekening (atas nama)')),
            if (adding && store.estates.length > 1) ...[
              const SizedBox(height: 16),
              Text('Tambahkan ke perumahan',
                  style: Theme.of(context).textTheme.labelLarge),
              EstateChecklist(
                selected: _estates,
                onChanged: (v) => setState(() => _estates = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: _estates.isEmpty
              ? null
              : () => Navigator.pop(context, (
                    BankAccount(
                      title: _title.text.trim(),
                      bankName: _bank.text.trim(),
                      accountNumber: _number.text.trim(),
                      accountName: _name.text.trim(),
                    ),
                    _estates,
                  )),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
