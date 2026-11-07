import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()); // mode demo, data contoh baru

  test('data contoh: 2 cluster, 4 blok, 48 rumah, warga tertaut ke rumah', () {
    expect(s.clusters, hasLength(2));
    expect(s.blocks, hasLength(4));
    expect(s.houses, hasLength(48));
    final budi = s.residentById('R1')!;
    expect(budi.houseId, isNotNull);
    expect(s.houseLabel(s.houseById(budi.houseId!)!), 'A1/05');
  });

  test('tambah nomor rumah: nomor yang sudah ada dilewati', () async {
    final a1 = s.blocks.firstWhere((b) => b.name == 'A1');
    final added = await s.addHouses(a1.id, ['12', '13', '14', '13']);
    expect(added, 2);
    expect(s.housesOf(a1.id).map((h) => h.number).last, '14');
  });

  test('tambah warga dari master rumah', () async {
    final a1 = s.blocks.firstWhere((b) => b.name == 'A1');
    final free = s.housesOf(a1.id).firstWhere((h) => h.number == '01');
    await s.addResident('Warga Baru', free.id, '0811');
    final r = s.residentOfHouse(free.id)!;
    expect(r.name, 'Warga Baru');
    expect(r.houseNo, 'A1/01');

    // Rumah yang sama tidak bisa diisi dua kali.
    expect(s.addResident('Lainnya', free.id, '0812'), throwsStateError);
  });

  test('tidak bisa menghapus data yang masih dipakai', () async {
    final budi = s.residentById('R1')!;
    final house = s.houseById(budi.houseId!)!;
    expect(s.deleteHouse(house.id), throwsStateError);
    expect(s.deleteBlock(house.blockId), throwsStateError);
    expect(s.deleteCluster(house.clusterId), throwsStateError);
  });

  test('nama cluster & blok tidak boleh dobel', () async {
    expect(s.saveCluster('cluster anggrek'), throwsStateError);
    await s.saveCluster('Cluster Cempaka');
    final c = s.clusters.firstWhere((c) => c.name == 'Cluster Cempaka');
    await s.saveBlock(c.id, 'C1');
    expect(s.saveBlock(c.id, 'c1'), throwsStateError);
  });

  test('urutan nomor rumah alami', () {
    final list = ['10', '2', '10A', '1', 'B'];
    list.sort(compareHouseNumber);
    expect(list, ['1', '2', '10', '10A', 'B']);
  });
}
