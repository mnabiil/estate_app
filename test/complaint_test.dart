import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late EstateStore s;

  setUp(() => s = EstateStore());

  test('pengelola menonaktifkan fitur keluhan: warga tidak bisa membuat', () async {
    s.login(Role.pengelola);
    expect(s.complaintsEnabled, isTrue);
    await s.setComplaintsEnabled(false);

    s.login(Role.warga, residentId: 'R1');
    expect(s.complaintsEnabled, isFalse);
    expect(s.addComplaint('Air mati', 'Sejak pagi', 'Fasilitas'),
        throwsStateError);

    s.login(Role.pengelola);
    await s.setComplaintsEnabled(true);
    s.login(Role.warga, residentId: 'R1');
    await s.addComplaint('Air mati', 'Sejak pagi', 'Fasilitas');
    expect(s.complaints.any((c) => c.title == 'Air mati'), isTrue);
  });

  test('saklar keluhan hanya untuk hak keluhan / master data', () {
    s.login(Role.pengelola, staffId: 'S-SARI'); // bendahara
    expect(s.setComplaintsEnabled(false), throwsStateError);
    s.login(Role.warga, residentId: 'R1');
    expect(s.setComplaintsEnabled(false), throwsStateError);
  });

  test('setiap perubahan status tercatat dengan catatan & foto', () async {
    s.login(Role.pengelola);
    final c = s.complaints.firstWhere((c) => c.status == ComplaintStatus.baru,
        orElse: () => s.complaints.first);
    final before = c.updates.length;

    await s.updateComplaintStatus(c.id, ComplaintStatus.diproses,
        note: 'Teknisi dijadwalkan besok pagi',
        photos: [XFile('/tmp/cek.jpg')]);
    expect(c.status, ComplaintStatus.diproses);
    expect(c.updates.length, before + 1);
    expect(c.updates.last.note, 'Teknisi dijadwalkan besok pagi');
    expect(c.updates.last.photos, ['/tmp/cek.jpg']);
    expect(c.updates.last.by, 'Pak Hendra');

    // Status sama tapi ada catatan progres: tetap tercatat.
    await s.updateComplaintStatus(c.id, ComplaintStatus.diproses,
        note: 'Menunggu suku cadang');
    expect(c.updates.length, before + 2);

    // Tanpa perubahan apa pun ditolak.
    expect(s.updateComplaintStatus(c.id, ComplaintStatus.diproses),
        throwsStateError);
    // Maks. 3 foto.
    expect(
        s.updateComplaintStatus(c.id, ComplaintStatus.selesai,
            photos: List.generate(4, (i) => XFile('/tmp/$i.jpg'))),
        throwsStateError);

    await s.updateComplaintStatus(c.id, ComplaintStatus.selesai,
        note: 'Sudah diperbaiki', photos: [XFile('/tmp/beres.jpg')]);
    expect(c.status, ComplaintStatus.selesai);
  });
}
