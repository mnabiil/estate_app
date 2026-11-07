import 'package:estate_app/excel_io.dart';
import 'package:estate_app/import_plan.dart';
import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';

/// Membuat file .xlsx dari daftar baris per sheet (baris pertama = judul).
List<int> workbook(Map<String, List<List<Object?>>> sheets) {
  final book = xl.Excel.createExcel();
  final first = book.getDefaultSheet()!;
  var renamed = false;
  sheets.forEach((name, rows) {
    if (!renamed) {
      book.rename(first, name);
      renamed = true;
    }
    for (final row in rows) {
      book[name].appendRow([
        for (final v in row)
          v is int ? xl.IntCellValue(v) : xl.TextCellValue('${v ?? ''}'),
      ]);
    }
  });
  return book.encode()!;
}

const rumahHeader = [
  'Cluster', 'Tipe', 'Luas Bangunan', 'Luas Tanah', 'Blok', 'No. Rumah'
];
const wargaHeader = ['Nama', 'Cluster', 'Blok', 'No. Rumah', 'No. HP', 'Email'];

void main() {
  late EstateStore s;

  setUp(() {
    s = EstateStore(); // mode demo
    s.login(Role.pengelola);
  });

  group('nomor rumah', () {
    test('rentang, daftar, dan nomor khusus', () {
      expect(expandHouseNumbers('01-03, 7; 12A'), ['01', '02', '03', '7', '12A']);
      expect(expandHouseNumbers('8-11'), ['8', '9', '10', '11']);
      expect(expandHouseNumbers('098-101'), ['098', '099', '100', '101']);
      expect(() => expandHouseNumbers('5-2'), throwsFormatException);
      expect(() => expandHouseNumbers('1-400'), throwsFormatException);
    });

    test('disingkat kembali untuk ekspor', () {
      expect(compressHouseNumbers(['01', '02', '03', '05', '06', '12A']),
          '01-03, 05, 06, 12A');
      expect(compressHouseNumbers(['1', '2', '3', '4']), '1-4');
    });

    test('nol di depan diabaikan saat membandingkan', () {
      expect(normNumber('05'), normNumber('5'));
      expect(normNumber('0'), '0');
      expect(normNumber('012A'), '12a');
    });
  });

  test('template contoh: data yang sudah ada dilewati, sisanya ditambah',
      () async {
    final plan = parseWorkbook(buildTemplate(), s);
    expect(plan.errors, isEmpty);
    expect(plan.clusters, ['Cluster Melati']);
    expect(plan.types.map((t) => t.name), ['Tipe 60/120']);
    expect(plan.blocks.map((b) => b.name), ['M1']);
    // A1: 01-20 (01-12 sudah ada) + A2: 01-15, 16A (01-12 sudah ada) + M1: 1-10
    expect(plan.houses, hasLength(8 + 4 + 10));
    expect(plan.existingHouses, 24);
    // Budi Santoso sudah menempati A1/05.
    expect(plan.existingResidents, 1);
    expect(plan.residents, isEmpty);

    final before = s.houses.length;
    final result = await s.applyImport(plan);
    expect(result.houses, 22);
    expect(s.houses.length, before + 22);
    final melati = s.clusters.firstWhere((c) => c.name == 'Cluster Melati');
    final m1 = s.blocksOf(melati.id).single;
    expect(s.houseTypeById(m1.typeId)!.name, 'Tipe 60/120');
    expect(s.houseTypeById(m1.typeId)!.buildingArea, 60);
    expect(s.housesOf(m1.id).map((h) => h.number).first, '1');

    // Diunggah ulang: tidak ada yang digandakan.
    final again = parseWorkbook(buildTemplate(), s);
    expect(again.isEmpty, isTrue);
    expect(again.errors, isEmpty);
  });

  test('ekspor lalu impor ulang: tidak ada data baru', () {
    final plan = parseWorkbook(buildExport(s), s);
    expect(plan.errors, isEmpty);
    expect(plan.isEmpty, isTrue);
    expect(plan.existingHouses, s.houses.length);
    // Warga yang sudah terhubung ke rumah ikut diekspor.
    expect(plan.existingResidents,
        s.residents.where((r) => r.houseId != null).length);
  });

  test('import warga ke rumah baru', () async {
    final plan = parseWorkbook(
        workbook({
          'Rumah': [
            rumahHeader,
            ['Cluster Melati', 'Tipe 60/120', 60, 120, 'M1', '01-05'],
          ],
          'Warga': [
            wargaHeader,
            ['Agus Salim', 'cluster melati', 'm1', '1', '0811', 'agus@x.id'],
            ['Wati', 'Cluster Anggrek', 'A1', '1', '0812', ''],
          ],
        }),
        s);
    expect(plan.errors, isEmpty);
    expect(plan.residents, hasLength(2));
    final result = await s.applyImport(plan);
    expect(result.residents, 2);
    final agus = s.residents.firstWhere((r) => r.name == 'Agus Salim');
    expect(agus.houseNo, 'M1/01');
    expect(agus.email, 'agus@x.id');
    final wati = s.residents.firstWhere((r) => r.name == 'Wati');
    expect(wati.houseNo, 'A1/01');
  });

  test('error per baris', () {
    final plan = parseWorkbook(
        workbook({
          'Rumah': [
            rumahHeader,
            ['Cluster Anggrek', '', null, null, 'A9', '1-3'], // tipe kosong
            ['Cluster Anggrek', 'Tipe 45/90', 45, 90, 'A1', '30'], // A1 = 36/72
            ['Cluster Baru', 'Tipe X', 'abc', null, 'X1', '1'], // luas bukan angka
            ['Cluster Baru', 'Tipe X', null, null, 'X2', '9-2'], // rentang terbalik
            ['Cluster Baru', 'Tipe X', null, null, 'X3', '1'],
            ['Cluster Baru', 'Tipe Y', null, null, 'X3', '2'], // X3 dua tipe
          ],
          'Warga': [
            wargaHeader,
            ['Tono', 'Cluster Anggrek', 'Z9', '1', '0811', 't@x.id'], // rumah tak ada
            ['Tini', 'Cluster Anggrek', 'A1', '05', '0812', 'tini@x.id'], // ditempati Budi
            ['Tuti', 'Cluster Anggrek', 'A1', '02', '0813', 'bukan-email'],
          ],
        }),
        s);
    String errorAt(String where) =>
        plan.errors.firstWhere((e) => e.startsWith(where), orElse: () => '');
    expect(errorAt('Rumah baris 2'), contains('Tipe kosong'));
    expect(errorAt('Rumah baris 3'), contains('sudah bertipe Tipe 36/72'));
    expect(errorAt('Rumah baris 4'), contains('luas'));
    expect(errorAt('Rumah baris 5'), contains('terbalik'));
    expect(errorAt('Rumah baris 7'), contains('dua tipe'));
    expect(errorAt('Warga baris 2'), contains('tidak ada'));
    expect(errorAt('Warga baris 3'), contains('ditempati Budi Santoso'));
    expect(errorAt('Warga baris 4'), contains('email'));
    expect(plan.hasErrors, isTrue);
    expect(s.applyImport(plan), throwsStateError);
  });

  test('email wajib di mode online', () {
    final plan = parseWorkbook(
        workbook({
          'Warga': [
            wargaHeader,
            ['Wati', 'Cluster Anggrek', 'A1', '1', '0812', ''],
          ],
        }),
        s,
        requireEmail: true);
    expect(plan.errors.single, contains('Email kosong'));
  });

  test('file bukan Excel ditolak dengan pesan jelas', () {
    final plan = parseWorkbook([1, 2, 3, 4], s);
    expect(plan.errors.single, contains('.xlsx'));
  });
}
