import 'package:estate_app/prayer/adzan_sounds.dart';
import 'package:estate_app/prayer/prayer_service.dart';
import 'package:estate_app/prayer/prayer_times.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nilai acuan dari pustaka referensi (adhan), dalam UTC agar tes tidak
/// bergantung zona waktu mesin.
void expectNear(DateTime actual, String expectedUtc, {int minutes = 1}) {
  final e = DateTime.parse('${expectedUtc}Z');
  final diff = actual.toUtc().difference(e).inMinutes.abs();
  expect(diff, lessThanOrEqualTo(minutes),
      reason: 'dapat ${actual.toUtc()}, acuan $e');
}

void main() {
  test('Kemenag RI · Jakarta 11 Nov 2026 (dengan ihtiyat 2 menit)', () {
    const calc = PrayerCalculator(latitude: -6.2088, longitude: 106.8456);
    final d = calc.day(DateTime(2026, 11, 11));
    expectNear(d[PrayerTime.subuh], '2026-11-10 21:06');
    expectNear(d[PrayerTime.syuruq], '2026-11-10 22:23');
    expectNear(d[PrayerTime.dzuhur], '2026-11-11 04:39');
    expectNear(d[PrayerTime.ashar], '2026-11-11 07:59');
    expectNear(d[PrayerTime.maghrib], '2026-11-11 10:50');
    expectNear(d[PrayerTime.isya], '2026-11-11 12:03');
    // Imsak = Subuh − 10 menit.
    expect(d[PrayerTime.subuh].difference(d[PrayerTime.imsak]),
        const Duration(minutes: 10));
  });

  test('Muslim World League · Denpasar 1 Mar 2027 (tanpa ihtiyat)', () {
    const calc = PrayerCalculator(
        latitude: -8.65, longitude: 115.2167, method: PrayerMethod.mwl);
    final d = calc.day(DateTime(2027, 3, 1));
    expectNear(d[PrayerTime.subuh], '2027-02-28 21:13');
    expectNear(d[PrayerTime.syuruq], '2027-02-28 22:23');
    expectNear(d[PrayerTime.dzuhur], '2027-03-01 04:32');
    expectNear(d[PrayerTime.ashar], '2027-03-01 07:35');
    expectNear(d[PrayerTime.maghrib], '2027-03-01 10:40');
    expectNear(d[PrayerTime.isya], '2027-03-01 11:46');
  });

  test('Umm al-Qura: Isya 90 menit setelah Maghrib; Hanafi: Ashar lebih akhir',
      () {
    const uq = PrayerCalculator(
        latitude: -6.2, longitude: 106.8, method: PrayerMethod.ummAlQura);
    final d = uq.day(DateTime(2026, 11, 11));
    expect(d[PrayerTime.isya].difference(d[PrayerTime.maghrib]),
        const Duration(minutes: 90));

    const syafii = PrayerCalculator(latitude: -6.2, longitude: 106.8);
    const hanafi = PrayerCalculator(
        latitude: -6.2, longitude: 106.8, madhab: AsrMadhab.hanafi);
    final day = DateTime(2026, 11, 11);
    expect(
        hanafi.day(day)[PrayerTime.ashar]
            .isAfter(syafii.day(day)[PrayerTime.ashar]),
        isTrue);
  });

  test('sepertiga malam terakhir: 2/3 malam setelah Maghrib', () {
    const calc = PrayerCalculator(latitude: -6.2088, longitude: 106.8456);
    final today = calc.day(DateTime(2026, 11, 11));
    final tomorrow = calc.day(DateTime(2026, 11, 12));
    final third = today[PrayerTime.sepertigaMalam];
    expect(third.isAfter(today[PrayerTime.isya]), isTrue);
    expect(third.isBefore(tomorrow[PrayerTime.subuh]), isTrue);
    final night = tomorrow[PrayerTime.subuh]
        .difference(today[PrayerTime.maghrib])
        .inMinutes;
    expect(third.difference(today[PrayerTime.maghrib]).inMinutes,
        closeTo(night * 2 / 3, 1));
  });

  test('waktu berikutnya & urutan dalam sehari', () {
    const calc = PrayerCalculator(latitude: -6.2088, longitude: 106.8456);
    final d = calc.day(DateTime(2026, 11, 11));
    final order = [
      PrayerTime.imsak,
      PrayerTime.subuh,
      PrayerTime.syuruq,
      PrayerTime.dzuhur,
      PrayerTime.ashar,
      PrayerTime.maghrib,
      PrayerTime.isya,
      PrayerTime.sepertigaMalam,
    ];
    for (var i = 1; i < order.length; i++) {
      expect(d[order[i]].isAfter(d[order[i - 1]]), isTrue,
          reason: '${order[i]} setelah ${order[i - 1]}');
    }
    final afterDzuhur = d[PrayerTime.dzuhur].add(const Duration(minutes: 1));
    expect(calc.next(afterDzuhur)!.$1, PrayerTime.ashar);
    final afterIsya = d[PrayerTime.isya].add(const Duration(minutes: 1));
    final next = calc.next(afterIsya)!;
    expect(next.$1, PrayerTime.subuh);
    expect(next.$2.isAfter(afterIsya), isTrue);
  });

  test('jadwal sebulan', () {
    const calc = PrayerCalculator(latitude: -6.2088, longitude: 106.8456);
    expect(calc.month(2027, 2), hasLength(28));
    expect(calc.month(2026, 11), hasLength(30));
  });

  test('arah kiblat Jakarta ± 295°', () {
    expect(qiblaBearing(-6.2088, 106.8456), closeTo(295.15, 0.1));
  });

  test('tanggal Hijriah & koreksi', () {
    final h = HijriDate.fromGregorian(DateTime(2026, 2, 18));
    expect((h.year, h.month, h.day), (1447, 9, 1));
    expect(h.isRamadan, isTrue);
    expect(h.toString(), '1 Ramadhan 1447 H');
    final adj = HijriDate.fromGregorian(DateTime(2026, 2, 18), adjustDays: -1);
    expect(adj.isRamadan, isFalse);
  });

  test('pengaturan adzan tersimpan per akun', () async {
    final p = PrayerService.instance;
    await p.attach('warga/budi');
    expect(p.settings.decided, isFalse);
    await p.update((s) {
      s.method = PrayerMethod.mwl;
      s.active = {PrayerTime.subuh, PrayerTime.maghrib, PrayerTime.sepertigaMalam};
      s.reminderMinutes = 10;
    });
    await p.setEnabled(true);

    await p.attach('warga/siti');
    expect(p.settings.enabled, isFalse);
    expect(p.settings.method, PrayerMethod.kemenag);

    await p.attach('warga/budi');
    expect(p.settings.enabled, isTrue);
    expect(p.settings.decided, isTrue);
    expect(p.settings.method, PrayerMethod.mwl);
    expect(p.settings.active,
        {PrayerTime.subuh, PrayerTime.maghrib, PrayerTime.sepertigaMalam});
    expect(p.settings.reminderMinutes, 10);
  });

  test('suara adzan: Subuh khusus hanya untuk waktu Subuh; bawaan', () {
    final subuhOnly = adzanSounds.where((s) => s.subuhOnly).map((s) => s.id);
    expect(subuhOnly, ['subuh_madinah']);
    final settings = PrayerSettings();
    expect(settings.soundId, 'makkah');
    expect(settings.subuhSoundId, 'subuh_madinah');
    expect(adzanSoundById('tidak-ada').id, 'default');
    for (final s in adzanSounds.where((s) => !s.isDefault)) {
      expect(s.androidRaw, startsWith('adzan_'));
      expect(s.iosFile, endsWith('.caf'));
    }
  });
}

