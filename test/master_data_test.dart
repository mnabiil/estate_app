import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()); // mode demo, data contoh baru

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
        ['Perumahan Griya Asri', 'Nilaya Residence']);
    expect(s.residents, hasLength(8));

    await s.switchEstate('nilaya-residence');
    expect(s.estateName, 'Nilaya Residence');
    expect(s.fee, 300000);
    expect(s.residents, isEmpty);
    expect(s.clusters.single.name, 'Cluster Melati');
    expect(s.houses, hasLength(8));

    await s.switchEstate('griya-asri');
    expect(s.residents, hasLength(8));
    expect(s.clusters, hasLength(2));

    await s.createEstate(name: 'Nilaya Hills', address: 'Bogor', fee: 275000);
    expect(s.estates, hasLength(3));
    expect(s.estateName, 'Nilaya Hills');
    expect(s.clusters, isEmpty);
    expect(s.createEstate(name: 'nilaya hills', address: '', fee: 1),
        throwsStateError);
  });

  test('urutan nomor rumah alami', () {
    final list = ['10', '2', '10A', '1', 'B'];
    list.sort(compareHouseNumber);
    expect(list, ['1', '2', '10', '10A', 'B']);
  });
}
