import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore()..login(Role.pengelola, staffId: 'S-HENDRA'));

  test('pengumuman dengan foto & batas berlaku; warga hanya lihat yang aktif',
      () async {
    final today = dateOnly(DateTime.now());
    await s.addAnnouncement('Lomba 17-an', 'Daftar di pos RT',
        until: today.add(const Duration(days: 3)),
        photo: XFile('/tmp/lomba.jpg'));
    final a = s.visibleAnnouncements.first;
    expect(a.title, 'Lomba 17-an');
    expect(a.photoUrl, '/tmp/lomba.jpg');
    expect(a.createdBy, 'Pak Hendra');
    expect(a.isActiveOn(today.add(const Duration(days: 3))), isTrue);
    expect(a.isActiveOn(today.add(const Duration(days: 4))), isFalse);

    // Pengumuman lama yang sudah berakhir.
    s.announcements.add(Announcement(
      id: 'OLD',
      title: 'Pemadaman listrik',
      body: '',
      createdAt: today.subtract(const Duration(days: 10)),
      until: today.subtract(const Duration(days: 1)),
    ));
    expect(s.visibleAnnouncements.map((e) => e.id), contains('OLD'));
    s.login(Role.warga, residentId: 'R1');
    expect(s.visibleAnnouncements.map((e) => e.id), isNot(contains('OLD')));
    expect(s.deleteAnnouncement(a.id), throwsStateError);
  });

  test('validasi & hapus pengumuman', () async {
    expect(s.addAnnouncement('  ', 'isi'), throwsStateError);
    expect(
        s.addAnnouncement('Judul', 'isi',
            until: DateTime.now().subtract(const Duration(days: 2))),
        throwsStateError);
    await s.addAnnouncement('Hapus saya', '');
    final id = s.announcements.firstWhere((a) => a.title == 'Hapus saya').id;
    await s.deleteAnnouncement(id);
    expect(s.announcementById(id), isNull);
  });

  test('nominal deposit renovasi diatur pengelola berhak renovasi', () async {
    await s.setRenovationDeposits(1500000, 7500000);
    expect(s.depositFor(RenovationType.kecil), 1500000);
    expect(s.depositFor(RenovationType.besar), 7500000);
    expect(s.setRenovationDeposits(0, 1), throwsStateError);
    s.login(Role.pengelola, staffId: 'S-SARI'); // bendahara
    expect(s.setRenovationDeposits(1, 2), throwsStateError);
  });

  test('rekening baru bisa ditambahkan ke beberapa perumahan', () async {
    const acc = BankAccount(
        title: 'Rekening IPL',
        bankName: 'BRI',
        accountNumber: '0123-01-000123-30-1',
        accountName: 'Paguyuban Warga');
    await s.addBankAccount(acc, ['griya-asri', 'amani-residence']);
    expect(s.bankAccounts.last.title, 'Rekening IPL');
    await s.switchEstate('amani-residence');
    expect(s.bankAccounts.single.bankName, 'BRI');
    expect(s.addBankAccount(acc, const []), throwsStateError);
  });

  test('reset password anggota tim hanya oleh pemilik', () {
    expect(s.resetStaffPassword('S-HENDRA'), throwsStateError); // diri sendiri
    s.login(Role.pengelola, staffId: 'S-SARI');
    expect(s.resetStaffPassword('S-JOKO'), throwsStateError);
  });
}
