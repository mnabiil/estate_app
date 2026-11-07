import 'package:estate_app/models.dart';
import 'package:estate_app/push.dart';
import 'package:estate_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferensi notifikasi: default aktif, bisa dimatikan per jenis',
      () async {
    final s = EstateStore()..login(Role.warga, residentId: 'R1');
    expect(s.notifyAnnouncements, isTrue);
    expect(s.notifyBills, isTrue);

    await s.setNotificationPrefs(bills: false);
    expect(s.notifyAnnouncements, isTrue);
    expect(s.notifyBills, isFalse);

    await s.setNotificationPrefs(announcements: false, bills: true);
    expect(s.notifyAnnouncements, isFalse);
    expect(s.notifyBills, isTrue);
  });

  test('notifikasi yang diketuk diteruskan sebagai tujuan navigasi', () {
    final push = PushService.instance;
    final seen = <PushTarget?>[];
    void listener() => seen.add(push.target.value);
    push.target.addListener(listener);
    push.target.value = PushTarget.bills;
    push.target.value = null;
    push.target.value = PushTarget.announcements;
    push.target.removeListener(listener);
    push.target.value = null;
    expect(seen, [PushTarget.bills, null, PushTarget.announcements]);
  });
}
