import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()); // mode demo

  Future<String?> add(String residentId, String name,
          {String email = '', MemberRelation relation = MemberRelation.anak}) =>
      s.addMember(
        residentId: residentId,
        name: name,
        relation: relation,
        phone: '0811',
        email: email,
      );

  test('reset password warga hanya untuk pengelola, dan butuh Firebase',
      () async {
    s.login(Role.warga, residentId: 'R1');
    await expectLater(s.resetResidentPassword('R1'),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('Hanya pengelola'))));

    s.login(Role.pengelola);
    await expectLater(s.resetResidentPassword('R1'),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('mode Firebase'))));
  });

  test('data contoh: Budi (A1/05) punya anggota Ani', () {
    final members = s.membersOf('R1');
    expect(members.single.name, 'Ani Santoso');
    expect(members.single.relation, MemberRelation.pasangan);
  });

  test('kepala keluarga menambah & menghapus anggota', () async {
    s.login(Role.warga, residentId: 'R1');
    expect(s.currentUser!.isPrimary, isTrue);
    expect(s.canManageMembers('R1'), isTrue);

    await add('R1', 'Dimas', email: 'dimas@contoh.id');
    await add('R1', 'Pak Kos', relation: MemberRelation.penyewa);
    expect(s.membersOf('R1').map((m) => m.name),
        ['Ani Santoso', 'Dimas', 'Pak Kos']);

    // Email dobel ditolak.
    expect(add('R1', 'Lain', email: 'DIMAS@contoh.id'), throwsStateError);

    final dimas = s.membersOf('R1').firstWhere((m) => m.name == 'Dimas');
    await s.removeMember(dimas.id);
    expect(s.membersOf('R1').map((m) => m.name), ['Ani Santoso', 'Pak Kos']);
  });

  test('maksimal anggota per rumah', () async {
    s.login(Role.warga, residentId: 'R1');
    for (var i = s.membersOf('R1').length; i < maxHouseholdMembers; i++) {
      await add('R1', 'Anggota $i');
    }
    expect(add('R1', 'Kelebihan'), throwsStateError);
  });

  test('anggota memakai data rumah yang sama, tapi tidak mengelola anggota',
      () async {
    s.login(Role.warga, memberId: 'M-ANI');
    final me = s.currentUser!;
    expect(me.name, 'Ani Santoso');
    expect(me.isPrimary, isFalse);
    expect(me.residentId, 'R1');
    expect(s.currentResident!.name, 'Budi Santoso');
    expect(s.unpaidTotal(me.residentId!), greaterThan(0));

    expect(s.canManageMembers('R1'), isFalse);
    expect(add('R1', 'Dimas'), throwsStateError);
    expect(s.removeMember('M-ANI'), throwsStateError);

    // Bisa mencatat barang renovasi rumahnya; tercatat atas namanya.
    final reno = s.renovations.firstWhere((r) => r.residentId == 'R1');
    await s.addRenovationLog(reno.id,
        direction: LogDirection.masuk, item: 'Cat', quantity: '1 pail');
    expect(s.logsOf(reno.id).first.recordedBy, 'Ani Santoso');
  });

  test('kepala keluarga lain tidak bisa mengelola rumah orang lain', () {
    s.login(Role.warga, residentId: 'R2');
    expect(s.canManageMembers('R1'), isFalse);
    expect(add('R1', 'Penyusup'), throwsStateError);
    expect(s.removeMember('M-ANI'), throwsStateError);
  });

  test('pengelola mengelola anggota rumah mana pun', () async {
    s.login(Role.pengelola);
    await add('R2', 'Rina Penyewa', relation: MemberRelation.penyewa);
    final m = s.membersOf('R2').single;
    expect(m.relation, MemberRelation.penyewa);
    await s.removeMember(m.id);
    expect(s.membersOf('R2'), isEmpty);
    await s.removeMember('M-ANI');
    expect(s.membersOf('R1'), isEmpty);
  });
}
