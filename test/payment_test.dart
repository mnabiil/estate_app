import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()); // mode demo

  test('rekening perumahan contoh tersedia', () {
    s.login(Role.warga, residentId: 'R3');
    expect(s.bankAccounts, isNotEmpty);
  });

  test('beberapa tagihan dibayar sekaligus, terlama wajib ikut', () async {
    s.login(Role.warga, residentId: 'R3');
    final unpaid = s.unpaidBillsOf('R3');
    expect(unpaid.length, greaterThanOrEqualTo(3));

    // Melompati tagihan terlama ditolak.
    expect(s.createPayment([unpaid[1].id]), throwsStateError);

    final p = await s.createPayment([unpaid[0].id, unpaid[1].id]);
    expect(p.billIds, [unpaid[0].id, unpaid[1].id]);
    expect(p.baseAmount, unpaid[0].amount + unpaid[1].amount);
    expect(p.uniqueCode, inInclusiveRange(1, 999));
    expect(p.total, p.baseAmount + p.uniqueCode);
    expect(p.reference, endsWith(p.uniqueCode.toString().padLeft(3, '0')));
    expect(s.isBillLocked(unpaid[0]), isTrue);
    expect(s.isBillLocked(unpaid[2]), isFalse);

    // Hanya satu pembayaran aktif per rumah.
    expect(s.createPayment([unpaid[2].id]), throwsStateError);
  });

  test('kode unik berbeda antar rumah yang sedang membayar', () async {
    final codes = <int>{
      for (final p in s.payments)
        if (p.isActiveOn(DateTime.now())) p.uniqueCode,
    };
    for (final rid in ['R1', 'R3', 'R4']) {
      s.login(Role.warga, residentId: rid);
      final unpaid = s.unpaidBillsOf(rid);
      if (unpaid.isEmpty) continue;
      final p = await s.createPayment([unpaid.first.id]);
      expect(codes.add(p.uniqueCode), isTrue, reason: 'kode $rid bentrok');
    }
  });

  test('alur: transfer -> unggah bukti -> ditolak -> unggah ulang -> diterima',
      () async {
    s.login(Role.warga, residentId: 'R3');
    final unpaid = s.unpaidBillsOf('R3');
    final p = await s.createPayment([for (final b in unpaid) b.id]);

    // Warga tidak bisa memverifikasi sendiri.
    expect(s.verifyPayment(p.id), throwsStateError);

    await s.submitPaymentProof(p.id, XFile('/tmp/bukti.jpg'));
    expect(p.status, PaymentStatus.menungguVerifikasi);

    // Satpam tidak punya hak tagihan.
    s.login(Role.pengelola, staffId: 'S-JOKO');
    expect(s.verifyPayment(p.id), throwsStateError);

    s.login(Role.pengelola, staffId: 'S-SARI'); // bendahara
    expect(s.paymentsToVerify.map((e) => e.id), contains(p.id));
    expect(s.rejectPayment(p.id, ''), throwsStateError);
    await s.rejectPayment(p.id, 'Nominal tidak sesuai');
    expect(p.status, PaymentStatus.ditolak);

    s.login(Role.warga, residentId: 'R3');
    await s.submitPaymentProof(p.id, XFile('/tmp/bukti2.jpg'));
    expect(p.status, PaymentStatus.menungguVerifikasi);

    s.login(Role.pengelola, staffId: 'S-SARI');
    await s.verifyPayment(p.id);
    expect(p.status, PaymentStatus.diterima);
    expect(s.unpaidTotal('R3'), 0);
    for (final b in s.billsForResident('R3')
        .where((b) => p.billIds.contains(b.id))) {
      expect(b.status, BillStatus.lunas);
      expect(b.paymentId, p.id);
    }
  });

  test('warga bisa membatalkan lalu membuat kode baru', () async {
    s.login(Role.warga, residentId: 'R3');
    final first = s.unpaidBillsOf('R3').first;
    final p = await s.createPayment([first.id]);
    await s.cancelPayment(p.id);
    expect(p.status, PaymentStatus.dibatalkan);
    expect(s.activePaymentOf('R3'), isNull);
    final again = await s.createPayment([first.id]);
    expect(again.id, isNot(p.id));
  });

  test('kedaluwarsa setelah batas waktu', () {
    final now = DateTime(2026, 11, 8, 10);
    final p = Payment(
      id: 'X',
      residentId: 'R1',
      billIds: const ['B'],
      baseAmount: 250000,
      uniqueCode: 12,
      reference: paymentReference('A1/05', 12),
      createdAt: now,
      expiresAt: now.add(paymentValidity),
    );
    expect(p.reference, 'IPL-A105-012');
    expect(p.statusOn(now), PaymentStatus.menungguTransfer);
    final later = now.add(const Duration(hours: 25));
    expect(p.statusOn(later), PaymentStatus.kedaluwarsa);
    expect(p.isActiveOn(later), isFalse);
    expect(p.canUploadProofOn(later), isFalse);
  });

  test('rekening hanya diatur pengelola dengan hak tagihan', () async {
    s.login(Role.pengelola, staffId: 'S-JOKO');
    expect(s.saveBankAccounts(const []), throwsStateError);
    s.login(Role.pengelola, staffId: 'S-SARI');
    await s.saveBankAccounts(const [
      BankAccount(bankName: 'BRI', accountNumber: '0123-01-000123-30-1', accountName: 'Paguyuban'),
    ]);
    expect(s.bankAccounts.single.bankName, 'BRI');
    expect(
        s.saveBankAccounts(const [
          BankAccount(bankName: 'BRI', accountNumber: 'abc', accountName: 'X'),
        ]),
        throwsStateError);
  });
}
