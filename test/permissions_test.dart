import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()); // mode demo

  test('pemilik: semua hak & mengatur tim', () {
    s.login(Role.pengelola);
    expect(s.isOwner, isTrue);
    expect(s.permissions, AdminPermission.values.toSet());
    s.login(Role.pengelola, staffId: 'S-HENDRA');
    expect(s.isOwner, isTrue);
  });

  test('bendahara hanya bisa urusan tagihan', () async {
    s.login(Role.pengelola, staffId: 'S-SARI');
    expect(s.isOwner, isFalse);
    expect(s.permissions, {AdminPermission.billing});

    await s.generateBillsForCurrentMonth(); // boleh
    expect(s.saveCluster('Cluster Baru'), throwsStateError);
    expect(s.addAnnouncement('Judul', 'Isi'), throwsStateError);
    expect(s.updateComplaintStatus(s.complaints.first.id, ComplaintStatus.selesai),
        throwsStateError);
    expect(s.saveAdminRole('Coba', {AdminPermission.masterData}),
        throwsStateError);
    expect(s.canManageMembers('R1'), isFalse);
  });

  test('satpam: check-in tamu & catat barang renovasi', () async {
    s.login(Role.pengelola, staffId: 'S-JOKO');
    await s.checkInVisitor(s.visitors.first.id);
    final running = s.renovations.firstWhere((r) => r.canWork);
    await s.addRenovationLog(running.id,
        direction: LogDirection.masuk, item: 'Pasir', quantity: '1 truk');
    expect(s.logsOf(running.id).first.recordedBy, 'Pak Joko');
    // Tidak boleh memproses ijin renovasi.
    expect(s.completeRenovation(running.id), throwsStateError);
  });

  test('pemilik mengubah level: hak anggota ikut berubah', () async {
    s.login(Role.pengelola);
    final bendahara = s.adminRoleById('L-BENDAHARA')!;
    await s.saveAdminRole('Bendahara',
        {AdminPermission.billing, AdminPermission.announcements},
        id: bendahara.id);

    s.login(Role.pengelola, staffId: 'S-SARI');
    expect(s.can(AdminPermission.announcements), isTrue);
    await s.addAnnouncement('Iuran', 'Mohon bayar IPL tepat waktu');
  });

  test('kelola tim: tambah, ganti level, keluarkan, pemilik terakhir', () async {
    s.login(Role.pengelola, staffId: 'S-HENDRA');
    await s.addStaff(
        name: 'Rina', email: 'rina@contoh.id', roleId: 'L-ADMIN-WARGA');
    final rina = s.staff.firstWhere((m) => m.name == 'Rina');
    expect(rina.permissions, contains(AdminPermission.residents));
    expect(s.addStaff(name: 'X', email: 'RINA@contoh.id'), throwsStateError);

    await s.setStaffRole(rina.id, 'L-SATPAM');
    expect(rina.roleName, 'Satpam');
    expect(rina.permissions, {AdminPermission.visitors, AdminPermission.renovationLogs});

    // Level yang masih dipakai tidak bisa dihapus.
    expect(s.deleteAdminRole('L-SATPAM'), throwsStateError);
    // Tidak bisa mengubah / mengeluarkan diri sendiri.
    expect(s.setStaffRole('S-HENDRA', 'L-SATPAM'), throwsStateError);
    expect(s.removeStaff('S-HENDRA'), throwsStateError);

    await s.removeStaff(rina.id);
    expect(s.staff.any((m) => m.name == 'Rina'), isFalse);
  });

  test('anggota tim bukan pemilik tidak bisa mengatur tim', () {
    s.login(Role.pengelola, staffId: 'S-SARI');
    expect(s.addStaff(name: 'X', email: 'x@contoh.id'), throwsStateError);
    expect(s.removeStaff('S-JOKO'), throwsStateError);
  });

  test('hak akses berlaku per perumahan', () async {
    s.login(Role.pengelola, staffId: 'S-SARI');
    await s.switchEstate('amani-residence');
    // Bu Sari tidak tercatat di tim Amani Residence: tanpa hak.
    expect(s.permissions, isEmpty);
    expect(s.isOwner, isFalse);
  });
}
