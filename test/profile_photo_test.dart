import 'package:estate_app/models.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('warga mengganti & menghapus foto profil; foto per akun', () async {
    final s = EstateStore()..login(Role.warga, residentId: 'R1');
    expect(s.profilePhotoUrl, isNull);
    await s.setProfilePhoto(XFile('/tmp/budi.jpg'));
    expect(s.profilePhotoUrl, '/tmp/budi.jpg');

    // Akun lain tidak ikut berubah.
    s.login(Role.warga, residentId: 'R2');
    expect(s.profilePhotoUrl, isNull);

    // Tetap ada setelah login ulang.
    s.login(Role.warga, residentId: 'R1');
    expect(s.profilePhotoUrl, '/tmp/budi.jpg');

    await s.setProfilePhoto(null);
    expect(s.profilePhotoUrl, isNull);
  });
}
