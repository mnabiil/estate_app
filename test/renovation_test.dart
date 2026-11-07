import 'dart:io';

import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late EstateStore s;
  late Directory tmp;
  final today = dateOnly(DateTime.now());

  setUp(() {
    s = EstateStore(); // mode demo
    tmp = Directory.systemTemp.createTempSync('renovasi_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  XFile file(String name, [int bytes = 1024]) {
    // Pakai pemisah path bawaan OS: di Windows XFile.name diambil dari
    // bagian setelah '\', jadi '/' akan ikut terbawa ke nama file.
    final f = File('${tmp.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(List.filled(bytes, 1));
    return XFile(f.path, name: name);
  }

  void asWarga(String residentId) => s.login(Role.warga, residentId: residentId);
  void asAdmin() => s.login(Role.pengelola);

  Future<Renovation> submit({
    RenovationType type = RenovationType.kecil,
    int startIn = 1,
    int days = 10,
    List<XFile> attachments = const [],
  }) async {
    await s.submitRenovation(
      type: type,
      description: 'Ganti kanopi carport dan cat pagar depan',
      contractor: 'Pak Udin',
      start: today.add(Duration(days: startIn)),
      end: today.add(Duration(days: startIn + days - 1)),
      attachments: attachments,
    );
    return s.renovations.last;
  }

  test('data contoh: berjalan, menunggu persetujuan, menunggu deposit', () {
    expect(s.renovations, hasLength(3));
    final running = s.renovations.firstWhere((r) => r.residentId == 'R1');
    expect(running.canWork, isTrue);
    expect(running.phaseOn(today), RenovationPhase.berjalan);
    expect(s.logsOf(running.id), hasLength(4));

    final pending = s.renovations.firstWhere((r) => r.residentId == 'R4');
    expect(pending.status, RenovationStatus.diajukan);
    expect(pending.attachments, hasLength(2));

    final approved = s.renovations.firstWhere((r) => r.residentId == 'R6');
    expect(approved.awaitingDeposit, isTrue);
  });

  test('deposit berbeda untuk renovasi kecil dan besar', () async {
    asWarga('R2');
    final kecil = await submit();
    expect(kecil.deposit, defaultDepositSmall);
    expect(kecil.durationDays, 10);

    asWarga('R3');
    final besar = await submit(type: RenovationType.besar);
    expect(besar.deposit, defaultDepositLarge);

    // Deposit mengikuti pengaturan perumahan.
    asAdmin();
    await s.updateEstate(
        name: s.estateName,
        address: s.estateAddress,
        fee: s.fee,
        depositSmall: 750000,
        depositLarge: 7500000);
    asWarga('R5');
    expect((await submit(type: RenovationType.besar)).deposit, 7500000);
  });

  test('pengajuan dengan lampiran file', () async {
    asWarga('R2');
    final r = await submit(attachments: [
      file('denah.pdf', 2048),
      file('desain.jpg', 4096),
    ]);
    expect(r.attachments.map((a) => a.name), ['denah.pdf', 'desain.jpg']);
    expect(r.attachments.first.size, 2048);
    expect(r.attachments.last.isImage, isTrue);
    expect(r.attachments.first.isImage, isFalse);
  });

  test('lampiran dibatasi jumlahnya', () async {
    asWarga('R2');
    expect(
        submit(attachments: [
          for (var i = 0; i <= maxRenovationAttachments; i++) file('f$i.pdf'),
        ]),
        throwsStateError);
  });

  test('alur: ajukan → disetujui → bayar deposit → verifikasi → log barang '
      '(dengan foto) → perpanjang → selesai → kembalikan deposit', () async {
    asWarga('R2');
    final r = await submit(attachments: [file('rab.pdf')]);
    expect(r.status, RenovationStatus.diajukan);
    expect(r.depositStatus, DepositStatus.belumBayar);

    // Deposit belum bisa dibayar sebelum ijin disetujui.
    expect(s.payDeposit(r.id, method: 'Transfer bank'), throwsStateError);

    // 1. Pengelola meninjau & menyetujui (tanpa menunggu deposit).
    asAdmin();
    await s.approveRenovation(r.id, note: 'Jam kerja 08.00-17.00');
    expect(r.status, RenovationStatus.disetujui);
    expect(r.awaitingDeposit, isTrue);
    expect(r.canWork, isFalse);

    // Pekerjaan belum boleh berjalan sebelum deposit diterima.
    expect(
        s.addRenovationLog(r.id,
            direction: LogDirection.masuk, item: 'Semen', quantity: '5 sak'),
        throwsStateError);
    expect(s.completeRenovation(r.id), throwsStateError);

    // 2. Warga membayar deposit + bukti transfer.
    asWarga('R2');
    await s.payDeposit(r.id,
        method: 'Transfer bank', proof: file('bukti.jpg'));
    expect(r.depositStatus, DepositStatus.menungguVerifikasi);
    expect(r.depositProofUrl, isNotNull);

    // Bukti ditolak → warga kirim ulang.
    asAdmin();
    await s.rejectDepositProof(r.id, 'Nominal tidak sesuai');
    expect(r.depositStatus, DepositStatus.belumBayar);
    expect(r.depositProofUrl, isNull);
    asWarga('R2');
    await s.payDeposit(r.id,
        method: 'Transfer bank', proof: file('bukti2.jpg'));

    // 3. Pengelola memverifikasi → pekerjaan berjalan.
    asAdmin();
    await s.markDepositPaid(r.id);
    expect(r.depositStatus, DepositStatus.dibayar);
    expect(r.canWork, isTrue);

    // Setelah deposit masuk, ijin tidak bisa dibatalkan sepihak.
    expect(s.cancelRenovation(r.id), throwsStateError);

    // 4. Catat barang masuk/keluar dengan foto.
    asWarga('R2');
    await s.addRenovationLog(r.id,
        direction: LogDirection.masuk,
        item: 'Semen',
        quantity: '5 sak',
        photos: [file('semen.jpg')]);
    asAdmin();
    await s.addRenovationLog(r.id,
        direction: LogDirection.keluar,
        item: 'Puing',
        quantity: '2 karung',
        note: 'Ke TPS',
        photos: [file('p1.jpg'), file('p2.jpg')]);
    final logs = s.logsOf(r.id);
    expect(logs, hasLength(2));
    expect(logs.expand((l) => l.photos), hasLength(3));
    expect(logs.map((l) => l.recordedBy), contains('Pak Hendra'));
    expect(
        s.addRenovationLog(r.id,
            direction: LogDirection.masuk,
            item: 'Pasir',
            quantity: '1 truk',
            photos: [for (var i = 0; i <= maxLogPhotos; i++) file('x$i.jpg')]),
        throwsStateError);

    // 5. Perpanjang, selesai, kembalikan deposit (dipotong).
    final newEnd = r.endDate.add(const Duration(days: 5));
    expect(s.extendRenovation(r.id, r.endDate), throwsStateError);
    await s.extendRenovation(r.id, newEnd);
    expect(r.durationDays, 15);

    expect(s.refundDeposit(r.id, r.deposit), throwsStateError);
    await s.completeRenovation(r.id, note: 'Bersih');
    expect(r.status, RenovationStatus.selesai);
    expect(s.refundDeposit(r.id, r.deposit + 1), throwsStateError);
    await s.refundDeposit(r.id, r.deposit - 200000, note: 'Aspal rusak');
    expect(r.depositStatus, DepositStatus.dikembalikan);
    expect(r.depositRefund, r.deposit - 200000);
  });

  test('pengelola bisa mencatat deposit tunai langsung', () async {
    final approved = s.renovations.firstWhere((r) => r.residentId == 'R6');
    asAdmin();
    await s.markDepositPaid(approved.id);
    expect(approved.canWork, isTrue);
    expect(approved.depositMethod, 'Tunai ke pengelola');
  });

  test('pembatalan sebelum deposit dibayar', () async {
    asWarga('R2');
    final r = await submit();
    await s.cancelRenovation(r.id);
    expect(r.status, RenovationStatus.dibatalkan);

    // Sudah disetujui tapi belum bayar: masih bisa dibatalkan.
    final r2 = await submit();
    asAdmin();
    await s.approveRenovation(r2.id);
    asWarga('R2');
    await s.cancelRenovation(r2.id);
    expect(r2.status, RenovationStatus.dibatalkan);

    // Sudah kirim pembayaran: tidak bisa dibatalkan warga.
    final r3 = await submit();
    asAdmin();
    await s.approveRenovation(r3.id);
    asWarga('R2');
    await s.payDeposit(r3.id, method: 'Tunai ke pengelola');
    expect(s.cancelRenovation(r3.id), throwsStateError);
  });

  test('validasi pengajuan', () async {
    asWarga('R2');
    expect(
        s.submitRenovation(
          type: RenovationType.kecil,
          description: 'x',
          contractor: 'y',
          start: today.add(const Duration(days: 5)),
          end: today.add(const Duration(days: 2)),
        ),
        throwsStateError);
    await submit();
    // Satu rumah hanya boleh punya satu ijin aktif.
    expect(submit(), throwsStateError);

    // Warga lain tidak bisa mencatat barang / membayar deposit orang lain.
    final running = s.renovations.firstWhere((r) => r.residentId == 'R1');
    expect(
        s.addRenovationLog(running.id,
            direction: LogDirection.masuk, item: 'Pasir', quantity: '1 truk'),
        throwsStateError);
    final approved = s.renovations.firstWhere((r) => r.residentId == 'R6');
    expect(s.payDeposit(approved.id, method: 'Transfer bank'), throwsStateError);
  });

  test('tahap pekerjaan dihitung dari tanggal', () {
    final r = Renovation(
      id: 'x',
      residentId: 'R1',
      type: RenovationType.kecil,
      description: '',
      contractor: '',
      startDate: DateTime(2026, 1, 10),
      endDate: DateTime(2026, 1, 20),
      deposit: 1,
      createdAt: DateTime(2026),
    );
    expect(r.phaseOn(DateTime(2026, 1, 9)), RenovationPhase.belumMulai);
    expect(r.phaseOn(DateTime(2026, 1, 20, 23)), RenovationPhase.berjalan);
    expect(r.phaseOn(DateTime(2026, 1, 21)), RenovationPhase.terlambat);
    expect(r.durationDays, 11);
  });
}
