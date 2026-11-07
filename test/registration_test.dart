import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()); // mode demo, belum login

  House house(String block, String number) {
    final b = s.blocks.firstWhere((b) => b.name == block);
    return s.housesOf(b.id).firstWhere((h) => h.number == number);
  }

  Future<void> register({
    required String name,
    required String email,
    required String houseId,
    String estateId = 'griya-asri',
  }) =>
      s.registerResident(
        estateId: estateId,
        houseId: houseId,
        name: name,
        phone: '0812-0000-1111',
        occupancy: Occupancy.pemilik,
        email: email,
        password: 'rahasia123',
      );

  group('password', () {
    test('aturan password', () {
      expect(passwordProblem('abc1'), isNotNull); // terlalu pendek
      expect(passwordProblem('abcdefgh'), isNotNull); // tanpa angka
      expect(passwordProblem('12345678'), isNotNull); // tanpa huruf
      expect(passwordProblem('rahasia123'), isNull);
    });

    test('wajib ganti password saat login pertama', () async {
      s.login(Role.warga, residentId: 'R1');
      s.currentUser = s.currentUser!.copyWith(mustChangePassword: true);

      expect(s.changePassword(newPassword: 'pendek1'), throwsStateError);
      await s.changePassword(newPassword: 'PasswordBaru1');
      expect(s.currentUser!.mustChangePassword, isFalse);
    });

    test('menu ganti password butuh password lama', () async {
      s.login(Role.pengelola);
      expect(s.changePassword(current: '', newPassword: 'PasswordBaru1'),
          throwsStateError);
      expect(s.changePassword(current: 'Lama1234', newPassword: 'Lama1234'),
          throwsStateError);
      await s.changePassword(current: 'Lama1234', newPassword: 'PasswordBaru1');
    });
  });

  group('registrasi mandiri', () {
    test('pilihan perumahan & rumah yang tersedia', () async {
      final estates = await s.registrationEstates();
      expect(estates.map((e) => e.id), ['griya-asri', 'nilaya-residence']);

      final o = await s.registrationOptions('griya-asri');
      expect(o.available.contains(house('A1', '01').id), isTrue);
      // Ditempati warga.
      expect(o.available.contains(house('A1', '05').id), isFalse);
      // Sedang diajukan pendaftar lain (data contoh).
      expect(o.available.contains(house('B1', '11').id), isFalse);
      // Tipe milik cluster, blok per tipe.
      final anggrek = o.clusters.firstWhere((c) => c.name == 'Cluster Anggrek');
      final t36 = o.typesOf(anggrek.id).first;
      expect(o.blocksOf(anggrek.id, t36.id).map((b) => b.name), ['A1']);
    });

    test('daftar → menunggu → disetujui pengelola → menjadi warga', () async {
      final target = house('A1', '01');
      await register(name: 'Rudi Baru', email: 'Rudi@Contoh.id', houseId: target.id);
      expect(s.currentUser!.role, Role.pendaftar);
      expect(s.myRegistration!.status, RegistrationStatus.menunggu);
      expect(s.myRegistration!.houseNo, 'A1/01');
      expect(s.myRegistration!.email, 'rudi@contoh.id');

      // Rumah tidak tersedia lagi untuk pendaftar lain.
      await s.logout();
      final o = await s.registrationOptions('griya-asri');
      expect(o.available.contains(target.id), isFalse);
      expect(
          register(name: 'Lain', email: 'lain@contoh.id', houseId: target.id),
          throwsStateError);
      // Email yang sama tidak bisa dipakai lagi.
      expect(
          register(
              name: 'X', email: 'rudi@contoh.id', houseId: house('A1', '02').id),
          throwsStateError);

      s.login(Role.pengelola);
      final reg = s.pendingRegistrations.firstWhere((r) => r.name == 'Rudi Baru');
      await s.approveRegistration(reg.id);
      expect(reg.status, RegistrationStatus.disetujui);
      final resident = s.residentOfHouse(target.id)!;
      expect(resident.name, 'Rudi Baru');
      expect(resident.houseNo, 'A1/01');
      expect(resident.email, 'rudi@contoh.id');
      expect(s.approveRegistration(reg.id), throwsStateError);
    });

    test('ditolak dengan alasan, lalu diperbaiki & diajukan ulang', () async {
      await register(
          name: 'Sari', email: 'sari@contoh.id', houseId: house('A1', '02').id);
      final reg = s.myRegistration!;
      // Pengelola menolak (disimulasikan langsung pada data demo).
      reg
        ..status = RegistrationStatus.ditolak
        ..note = 'Rumah A1/02 milik orang lain';

      await s.registerResident(
        estateId: 'griya-asri',
        houseId: house('A1', '03').id,
        name: 'Sari Wulandari',
        phone: '0812-0000-2222',
        occupancy: Occupancy.penyewa,
      );
      expect(s.myRegistration, same(reg));
      expect(reg.status, RegistrationStatus.menunggu);
      expect(reg.houseNo, 'A1/03');
      expect(reg.note, isEmpty);
      expect(reg.occupancy, Occupancy.penyewa);
    });

    test('pengelola menolak: alasan wajib', () async {
      s.login(Role.pengelola);
      final reg = s.pendingRegistrations
          .firstWhere((r) => r.name == 'Hendra Gunawan');
      expect(s.rejectRegistration(reg.id, ' '), throwsStateError);
      await s.rejectRegistration(reg.id, 'Data tidak sesuai');
      expect(reg.status, RegistrationStatus.ditolak);
      expect(reg.note, 'Data tidak sesuai');
      expect(s.pendingRegistrations.map((r) => r.name), ['Dimas Santoso']);
    });

    test('mendaftar ke perumahan lain (tidak aktif)', () async {
      final o = await s.registrationOptions('nilaya-residence');
      final m1 = o.blocks.single;
      final h = o.housesOf(m1.id).first;
      await register(
          name: 'Dina',
          email: 'dina@contoh.id',
          houseId: h.id,
          estateId: 'nilaya-residence');
      expect(s.myRegistration!.houseNo, 'M1/01');

      await s.logout();
      s.login(Role.pengelola);
      expect(s.pendingRegistrations.map((r) => r.name),
          ['Hendra Gunawan', 'Dimas Santoso']);
      await s.switchEstate('nilaya-residence');
      expect(s.pendingRegistrations.map((r) => r.name), ['Dina']);
    });

    test('pendaftaran ditutup tidak tampil di daftar perumahan', () async {
      s.login(Role.pengelola);
      await s.updateEstate(
          name: s.estateName,
          address: s.estateAddress,
          fee: s.fee,
          registrationOpen: false);
      final estates = await s.registrationEstates();
      expect(estates.map((e) => e.id), ['nilaya-residence']);
    });

    test('validasi data pendaftaran', () {
      expect(
          s.registerResident(
            estateId: 'griya-asri',
            houseId: house('A1', '01').id,
            name: 'A',
            phone: '08',
            occupancy: Occupancy.pemilik,
            email: 'bukan-email',
            password: 'rahasia123',
          ),
          throwsStateError);
      expect(
          s.registerResident(
            estateId: 'griya-asri',
            houseId: house('A1', '01').id,
            name: 'A',
            phone: '08',
            occupancy: Occupancy.pemilik,
            email: 'a@b.id',
            password: 'lemah',
          ),
          throwsStateError);
    });
  });

  group('gabung ke rumah berpenghuni', () {
    Future<void> join(String name, String email, House h,
            {MemberRelation relation = MemberRelation.penyewa}) =>
        s.registerResident(
          estateId: 'griya-asri',
          houseId: h.id,
          name: name,
          phone: '0812-3333-4444',
          occupancy: Occupancy.keluarga,
          email: email,
          password: 'rahasia123',
          relation: relation,
        );

    test('rumah berpenghuni bisa dipilih untuk gabung', () async {
      final o = await s.registrationOptions('griya-asri');
      final budiHouse = house('A1', '05');
      expect(o.occupied.contains(budiHouse.id), isTrue);
      expect(o.available.contains(budiHouse.id), isFalse);
      expect(o.selectable(budiHouse.id), isTrue);
      // Permintaan gabung tidak mengunci rumah.
      expect(o.selectable(house('A1', '01').id), isTrue);
    });

    test('gabung hanya ke rumah berpenghuni; warga baru hanya ke rumah kosong',
        () {
      expect(join('A', 'a@contoh.id', house('A1', '01')), throwsStateError);
      expect(register(name: 'B', email: 'b@contoh.id', houseId: house('A1', '05').id),
          throwsStateError);
    });

    test('kepala keluarga menyetujui permintaan gabung', () async {
      await join('Pak Kos', 'kos@contoh.id', house('A1', '05'));
      final reg = s.myRegistration!;
      expect(reg.isJoin, isTrue);
      expect(reg.residentId, 'R1');
      expect(reg.relation, MemberRelation.penyewa);
      await s.logout();

      // Kepala keluarga rumah lain & anggota rumah tidak berhak.
      s.login(Role.warga, residentId: 'R2');
      expect(s.canReviewRegistration(reg), isFalse);
      expect(s.approveRegistration(reg.id), throwsStateError);
      s.login(Role.warga, memberId: 'M-ANI');
      expect(s.canReviewRegistration(reg), isFalse);
      expect(s.rejectRegistration(reg.id, 'x'), throwsStateError);

      // Budi (kepala keluarga A1/05) melihat & menyetujui.
      s.login(Role.warga, residentId: 'R1');
      expect(s.joinRequestsFor('R1').map((r) => r.name),
          containsAll(['Pak Kos', 'Dimas Santoso']));
      expect(s.pendingRegistrations.map((r) => r.name),
          isNot(contains('Hendra Gunawan')));
      await s.approveRegistration(reg.id);
      expect(reg.status, RegistrationStatus.disetujui);
      final m = s.membersOf('R1').firstWhere((m) => m.name == 'Pak Kos');
      expect(m.relation, MemberRelation.penyewa);
      expect(m.email, 'kos@contoh.id');
    });

    test('kepala keluarga menolak; pengelola juga bisa menyetujui', () async {
      s.login(Role.warga, residentId: 'R1');
      final dimas = s.joinRequestsFor('R1').single;
      await s.rejectRegistration(dimas.id, 'Bukan anggota keluarga kami');
      expect(dimas.status, RegistrationStatus.ditolak);

      await s.logout();
      await join('Sinta', 'sinta@contoh.id', house('A1', '07'),
          relation: MemberRelation.anak);
      final reg = s.myRegistration!;
      await s.logout();
      s.login(Role.pengelola);
      await s.approveRegistration(reg.id);
      expect(s.membersOf(reg.residentId!).single.name, 'Sinta');
    });

    test('anggota rumah penuh', () async {
      s.login(Role.warga, residentId: 'R1');
      for (var i = s.membersOf('R1').length; i < maxHouseholdMembers; i++) {
        await s.addMember(
            residentId: 'R1',
            name: 'Anggota $i',
            relation: MemberRelation.anak,
            phone: '',
            email: '');
      }
      // Permintaan yang sudah masuk tidak bisa disetujui.
      final dimas = s.joinRequestsFor('R1').single;
      expect(s.approveRegistration(dimas.id), throwsStateError);
      await s.logout();
      // Permintaan baru ditolak sejak awal.
      expect(join('Telat', 'telat@contoh.id', house('A1', '05')),
          throwsStateError);
    });
  });
}
