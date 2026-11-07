import 'package:estate_app/excel_io.dart';
import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() {
    s = EstateStore()..login(Role.pengelola); // mode demo
  });

  House house(String block, String number) {
    final b = s.blocks.firstWhere((b) => b.name == block);
    return s.housesOf(b.id).firstWhere((h) => h.number == number);
  }

  HouseType typeOfBlock(String block) =>
      s.houseTypeById(s.blocks.firstWhere((b) => b.name == block).typeId)!;

  group('tanggal jatuh tempo', () {
    test('default tanggal 10; tagihan lama tanpa field tetap tanggal 10', () {
      expect(s.billDueDay, defaultBillDueDay);
      final bill = Bill(
          id: 'x', residentId: 'R1', period: DateTime(2026, 11), amount: 1);
      expect(bill.dueDate, DateTime(2026, 11, 10));
      expect(bill.isOverdueOn(DateTime(2026, 11, 10, 23)), isFalse);
      expect(bill.isOverdueOn(DateTime(2026, 11, 11)), isTrue);
      bill.status = BillStatus.lunas;
      expect(bill.isOverdueOn(DateTime(2026, 12)), isFalse);
    });

    test('hanya 1–28', () {
      expect(dueDateFor(DateTime(2026, 2), 31), DateTime(2026, 2, 28));
      expect(
          s.updateEstate(
              name: s.estateName,
              address: s.estateAddress,
              fee: s.fee,
              billDueDay: 29),
          throwsStateError);
      expect(
          s.updateEstate(
              name: s.estateName,
              address: s.estateAddress,
              fee: s.fee,
              billDueDay: 0),
          throwsStateError);
    });

    test('tagihan baru mengikuti tanggal & tarif yang berlaku', () async {
      await s.updateEstate(
          name: s.estateName,
          address: s.estateAddress,
          fee: 300000,
          billDueDay: 5);
      expect(s.billDueDay, 5);

      // Tarif khusus untuk Tipe 36/72 (blok A1); Tipe 54/108 (B2) tanpa tarif.
      final t36 = typeOfBlock('A1');
      await s.saveHouseType(t36.clusterId, t36.name,
          id: t36.id,
          buildingArea: t36.buildingArea,
          landArea: t36.landArea,
          monthlyFee: 225000);

      await s.addResident('Warga A1', house('A1', '01').id, '0811');
      await s.addResident('Warga B2', house('B2', '01').id, '0812');
      final created = await s.generateBillsForCurrentMonth();
      expect(created, 2);

      final now = DateTime.now();
      final period = DateTime(now.year, now.month);
      Bill billOf(String name) {
        final r = s.residents.firstWhere((r) => r.name == name);
        return s.bills
            .firstWhere((b) => b.residentId == r.id && b.period == period);
      }

      expect(billOf('Warga A1').amount, 225000);
      expect(billOf('Warga B2').amount, 300000);
      expect(billOf('Warga A1').dueDate, DateTime(now.year, now.month, 5));
    });
  });

  group('tarif per tipe rumah', () {
    test('tarif tipe dipakai bila diatur, selain itu tarif perumahan', () async {
      final budi = s.residentById('R1')!; // A1 -> Tipe 36/72
      expect(s.feeForResident(budi), s.fee);

      final t36 = typeOfBlock('A1');
      await s.saveHouseType(t36.clusterId, t36.name,
          id: t36.id, monthlyFee: 200000);
      expect(s.feeForResident(budi), 200000);

      // Warga lama yang belum terhubung ke rumah: tarif perumahan.
      final bayu = s.residents.firstWhere((r) => r.name == 'Bayu Saputra');
      expect(s.feeForResident(bayu), s.fee);

      // Hapus tarif tipe -> kembali ke tarif perumahan.
      await s.saveHouseType(t36.clusterId, t36.name, id: t36.id);
      expect(s.feeForResident(budi), s.fee);
    });

    test('tarif tipe harus > 0', () {
      final t36 = typeOfBlock('A1');
      expect(
          s.saveHouseType(t36.clusterId, t36.name, id: t36.id, monthlyFee: 0),
          throwsStateError);
    });

    test('kolom Tarif IPL di import Excel', () async {
      final plan = parseWorkbook(buildTemplate(), s);
      expect(plan.errors, isEmpty);
      final melati = plan.types.single;
      expect(melati.name, 'Tipe 60/120');
      expect(melati.monthlyFee, 350000);
      await s.applyImport(plan);
      final t = s.houseTypes.firstWhere((t) => t.name == 'Tipe 60/120');
      expect(t.monthlyFee, 350000);

      // Ekspor menyertakan tarif, impor ulang tanpa perubahan.
      final again = parseWorkbook(buildExport(s), s);
      expect(again.isEmpty, isTrue);
      expect(again.warnings, isEmpty);
    });
  });
}
