import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()..login(Role.pengelola, staffId: 'S-HENDRA'));

  test('anggota tim bisa diberi akses beberapa perumahan', () async {
    await s.addStaff(
      name: 'Rina',
      email: 'rina@contoh.id',
      roleId: 'L-ADMIN-WARGA',
      estateIds: ['griya-asri', 'amani-residence'],
    );
    final rina = s.staff.firstWhere((m) => m.name == 'Rina');
    expect(s.staffEstateIds(rina), ['griya-asri', 'amani-residence']);
    expect(s.staffEstatesLabel(rina), '2 perumahan');

    // Di perumahan lain: anggota & levelnya ikut tersalin.
    await s.switchEstate('amani-residence');
    final there = s.staff.firstWhere((m) => m.name == 'Rina');
    expect(there.roleName, 'Admin Warga');
    expect(s.adminRoleById('L-ADMIN-WARGA'), isNotNull);
  });

  test('akses dicabut dari salah satu perumahan', () async {
    await s.addStaff(
      name: 'Rina',
      email: 'rina@contoh.id',
      roleId: 'L-SATPAM',
      estateIds: ['griya-asri', 'amani-residence'],
    );
    final rina = s.staff.firstWhere((m) => m.name == 'Rina');
    await s.setStaffEstates(rina.id, estateIds: ['griya-asri']);
    expect(s.staffEstateIds(rina), ['griya-asri']);
    expect(s.setStaffEstates(rina.id, estateIds: const []), throwsStateError);
    await s.switchEstate('amani-residence');
    expect(s.staff.any((m) => m.name == 'Rina'), isFalse);
  });

  test('semua perumahan: termasuk perumahan yang dibuat kemudian', () async {
    await s.addStaff(
      name: 'Rina',
      email: 'rina@contoh.id',
      roleId: 'L-BENDAHARA',
      allEstates: true,
    );
    final rina = s.staff.firstWhere((m) => m.name == 'Rina');
    expect(s.staffEstatesLabel(rina), 'Semua perumahan');

    await s.createEstate(name: 'Kepuh Persada', address: '', fee: 300000);
    expect(s.estateName, 'Kepuh Persada');
    final there = s.staff.firstWhere((m) => m.name == 'Rina');
    expect(there.allEstates, isTrue);
    expect(there.permissions, {AdminPermission.billing});
    // Pembuat tetap pemilik di perumahan baru.
    expect(s.isOwner, isTrue);
  });

  test('pengumuman bisa dikirim ke beberapa perumahan', () async {
    final before = s.announcements.length;
    await s.addAnnouncement('Kerja bakti', 'Minggu pagi',
        estateIds: ['griya-asri', 'amani-residence']);
    expect(s.announcements.length, before + 1);
    await s.switchEstate('amani-residence');
    expect(s.announcements.map((a) => a.title), contains('Kerja bakti'));

    // Hanya perumahan aktif (default).
    await s.addAnnouncement('Air mati', 'Jam 10-12');
    await s.switchEstate('griya-asri');
    expect(s.announcements.map((a) => a.title), isNot(contains('Air mati')));
  });
}
