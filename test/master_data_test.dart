import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  // Mode demo, data contoh baru; login sebagai pemilik (akses penuh).
  setUp(() => s = EstateStore()..login(Role.pengelola));

  HouseBlock block(String name) => s.blocks.firstWhere((b) => b.name == name);
  Cluster cluster(String name) => s.clusters.firstWhere((c) => c.name == name);

  test('data contoh: Cluster > Tipe > Blok > No. rumah', () {
    expect(s.clusters, hasLength(2));
    expect(s.houseTypes, hasLength(4));
    expect(s.blocks, hasLength(4));
    expect(s.houses, hasLength(48));

    final anggrek = cluster('Cluster Anggrek');
    expect(s.typesOf(anggrek.id).map((t) => t.name),
        ['Tipe 36/72', 'Tipe 45/90']);

    final budi = s.residentById('R1')!;
    final house = s.houseById(budi.houseId!)!;
    expect(s.houseLabel(house), 'A1/05');
    expect(s.houseTypeOf(house)!.name, 'Tipe 36/72');
  });

  test('blok difilter per tipe', () {
    final anggrek = cluster('Cluster Anggrek');
    final t45 = s.typesOf(anggrek.id).firstWhere((t) => t.name == 'Tipe 45/90');
    expect(s.blocksOf(anggrek.id, typeId: t45.id).map((b) => b.name), ['A2']);
    expect(s.blocksOf(anggrek.id, typeId: noTypeId), isEmpty);
  });

  test('tipe milik cluster: nama boleh sama di cluster lain', () async {
    final anggrek = cluster('Cluster Anggrek');
    final bougenville = cluster('Cluster Bougenville');
    // "Tipe 45/90" sudah ada di kedua cluster pada data contoh.
    expect(s.saveHouseType(anggrek.id, 'tipe 45/90'), throwsStateError);
    await s.saveHouseType(bougenville.id, 'Tipe 36/72',
        buildingArea: 36, landArea: 72);
    expect(s.typesOf(bougenville.id), hasLength(3));
  });

  test('blok wajib bertipe dari cluster yang sama', () async {
    final anggrek = cluster('Cluster Anggrek');
    final bougenville = cluster('Cluster Bougenville');
    final typeB = s.typesOf(bougenville.id).first;
    expect(s.saveBlock(anggrek.id, 'A3', typeId: typeB.id), throwsStateError);

    final typeA = s.typesOf(anggrek.id).first;
    await s.saveBlock(anggrek.id, 'A3', typeId: typeA.id);
    expect(block('A3').typeId, typeA.id);
    expect(s.saveBlock(anggrek.id, 'a3', typeId: typeA.id), throwsStateError);
  });

  test('tambah nomor rumah: nomor yang sudah ada dilewati', () async {
    final a1 = block('A1');
    final added = await s.addHouses(a1.id, ['12', '13', '14', '13']);
    expect(added, 2);
    expect(s.housesOf(a1.id).map((h) => h.number).last, '14');
    // Rumah baru mengikuti tipe bloknya.
    final h14 = s.housesOf(a1.id).last;
    expect(s.houseTypeOf(h14)!.name, 'Tipe 36/72');
  });

  test('tambah warga dari master rumah', () async {
    final free = s.housesOf(block('A1').id).firstWhere((h) => h.number == '01');
    await s.addResident('Warga Baru', free.id, '0811');
    final r = s.residentOfHouse(free.id)!;
    expect(r.name, 'Warga Baru');
    expect(r.houseNo, 'A1/01');
    expect(s.addResident('Lainnya', free.id, '0812'), throwsStateError);
  });

  test('tidak bisa menghapus data yang masih dipakai', () async {
    final house = s.houseById(s.residentById('R1')!.houseId!)!;
    final b = s.blockById(house.blockId)!;
    expect(s.deleteHouse(house.id), throwsStateError);
    expect(s.deleteBlock(b.id), throwsStateError);
    expect(s.deleteHouseType(b.typeId!), throwsStateError);
    expect(s.deleteCluster(house.clusterId), throwsStateError);
  });

  test('banyak perumahan: berpindah, data terpisah, tambah baru', () async {
    expect(s.estates.map((e) => e.name),
        ['Perumahan Griya Asri', 'Amani Residence']);
    expect(s.residents, hasLength(10));

    await s.switchEstate('amani-residence');
    expect(s.estateName, 'Amani Residence');
    expect(s.fee, 300000);
    // Satu-satunya warga: rumah kedua milik akun Budi.
    expect(s.residents.single.name, 'Budi Santoso');
    expect(s.clusters.single.name, 'Cluster Melati');
    expect(s.houses, hasLength(8));

    await s.switchEstate('griya-asri');
    expect(s.residents, hasLength(10));
    expect(s.clusters, hasLength(2));

    await s.createEstate(name: 'Amani Hills', address: 'Bogor', fee: 275000);
    expect(s.estates, hasLength(3));
    expect(s.estateName, 'Amani Hills');
    expect(s.clusters, isEmpty);
    expect(s.createEstate(name: 'amani hills', address: '', fee: 1),
        throwsStateError);
  });

  test('warga lama: hubungkan otomatis bila nomor rumah cocok', () async {
    expect(s.unlinkedResidents.map((r) => r.name),
        ['Lina Hartati', 'Bayu Saputra']);
    final (linked, remaining) = await s.autoLinkResidents();
    expect(linked, 1);
    expect(remaining, 1);
    final lina = s.residents.firstWhere((r) => r.name == 'Lina Hartati');
    expect(s.houseLabel(s.houseById(lina.houseId!)!), 'A2/06');
    expect(s.unlinkedResidents.single.name, 'Bayu Saputra');
  });

  test('label cocok tanpa peduli huruf, spasi, dan nol di depan', () {
    expect(s.houseLabel(s.houseMatchingLabel('a1 / 5')!), 'A1/05');
    expect(s.houseMatchingLabel('Blok C 3'), isNull);
  });

  test('atur & pindah rumah warga', () async {
    final bayu = s.residents.firstWhere((r) => r.name == 'Bayu Saputra');
    final b2 = block('B2');
    final h11 = s.housesOf(b2.id).firstWhere((h) => h.number == '11');
    await s.assignHouse(bayu.id, h11.id);
    expect(bayu.houseNo, 'B2/11');
    expect(s.residentOfHouse(h11.id), bayu);

    // Rumah orang lain tidak bisa dipakai.
    final budiHouse = s.residentById('R1')!.houseId!;
    expect(s.assignHouse(bayu.id, budiHouse), throwsStateError);

    // Pindah: rumah lama jadi kosong.
    final h12 = s.housesOf(b2.id).firstWhere((h) => h.number == '12');
    await s.assignHouse(bayu.id, h12.id);
    expect(s.residentOfHouse(h11.id), isNull);
    expect(bayu.houseNo, 'B2/12');
  });

  test('urutan nomor rumah alami', () {
    final list = ['10', '2', '10A', '1', 'B'];
    list.sort(compareHouseNumber);
    expect(list, ['1', '2', '10', '10A', 'B']);
  });
}
