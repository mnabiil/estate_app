import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;
  final today = dateOnly(DateTime.now());

  setUp(() => s = EstateStore()); // mode demo

  void asWarga(String residentId) => s.login(Role.warga, residentId: residentId);
  void asAdmin() => s.login(Role.pengelola);

  Future<Renovation> submit({
    RenovationType type = RenovationType.kecil,
    int startIn = 1,
    int days = 10,
  }) async {
    await s.submitRenovation(
      type: type,
      description: 'Ganti kanopi',
      contractor: 'Pak Udin',
      start: today.add(Duration(days: startIn)),
      end: today.add(Duration(days: startIn + days - 1)),
    );
    return s.renovations.last;
  }

  test('data contoh: 1 berjalan dengan log barang, 1 menunggu deposit', () {
    expect(s.renovations, hasLength(2));
    final running = s.renovations.firstWhere((r) => r.residentId == 'R1');
    expect(running.status, RenovationStatus.disetujui);
    expect(running.phaseOn(today), RenovationPhase.berjalan);
    expect(s.logsOf(running.id), hasLength(4));
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

  test('alur lengkap: ajukan → deposit → setujui → log → perpanjang → '
      'selesai → kembalikan deposit', () async {
    asWarga('R2');
    final r = await submit();
    expect(r.status, RenovationStatus.diajukan);

    // Barang belum bisa dicatat sebelum disetujui.
    expect(
        s.addRenovationLog(r.id,
            direction: LogDirection.masuk, item: 'Semen', quantity: '5 sak'),
        throwsStateError);

    asAdmin();
    // Belum bisa disetujui sebelum deposit diterima.
    expect(s.approveRenovation(r.id), throwsStateError);
    await s.markDepositPaid(r.id);
    await s.approveRenovation(r.id, note: 'Jam kerja 08.00-17.00');
    expect(r.status, RenovationStatus.disetujui);

    asWarga('R2');
    await s.addRenovationLog(r.id,
        direction: LogDirection.masuk, item: 'Semen', quantity: '5 sak');
    asAdmin();
    await s.addRenovationLog(r.id,
        direction: LogDirection.keluar,
        item: 'Puing',
        quantity: '2 karung',
        note: 'Ke TPS');
    final logs = s.logsOf(r.id);
    expect(logs, hasLength(2));
    expect(logs.map((l) => l.recordedBy), contains('Pak Hendra'));

    // Perpanjang: harus setelah batas lama.
    expect(s.extendRenovation(r.id, r.endDate), throwsStateError);
    final newEnd = r.endDate.add(const Duration(days: 5));
    await s.extendRenovation(r.id, newEnd);
    expect(r.endDate, newEnd);
    expect(r.durationDays, 15);

    // Deposit belum bisa dikembalikan selama renovasi berjalan.
    expect(s.refundDeposit(r.id, r.deposit), throwsStateError);
    await s.completeRenovation(r.id, note: 'Bersih');
    expect(r.status, RenovationStatus.selesai);

    // Potongan tidak boleh melebihi deposit.
    expect(s.refundDeposit(r.id, r.deposit + 1), throwsStateError);
    await s.refundDeposit(r.id, r.deposit - 200000, note: 'Aspal rusak');
    expect(r.depositStatus, DepositStatus.dikembalikan);
    expect(r.depositRefund, r.deposit - 200000);
    expect(r.adminNote, 'Aspal rusak');

    // Selesai: tidak bisa mencatat barang lagi.
    expect(
        s.addRenovationLog(r.id,
            direction: LogDirection.masuk, item: 'Cat', quantity: '1'),
        throwsStateError);
  });

  test('validasi pengajuan', () async {
    asWarga('R2');
    // Tanggal selesai sebelum mulai.
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

    // Warga lain tidak bisa mencatat barang di renovasi orang lain.
    final running = s.renovations.firstWhere((r) => r.residentId == 'R1');
    expect(
        s.addRenovationLog(running.id,
            direction: LogDirection.masuk, item: 'Pasir', quantity: '1 truk'),
        throwsStateError);
  });

  test('warga membatalkan pengajuan sebelum bayar deposit', () async {
    asWarga('R2');
    final r = await submit();
    await s.cancelRenovation(r.id);
    expect(r.status, RenovationStatus.dibatalkan);
    expect(r.isActive, isFalse);
    // Setelah batal, boleh mengajukan lagi.
    await submit();
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
