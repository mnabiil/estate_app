import 'dart:math' as math;

/// Perhitungan jadwal sholat offline (tanpa internet), algoritma astronomi
/// standar (PrayTimes). Hasil sudah diuji terhadap pustaka referensi
/// dengan selisih < 1 menit untuk kota-kota di Indonesia.

/// Metode perhitungan waktu sholat.
enum PrayerMethod {
  kemenag('Kemenag RI', 'Subuh 20°, Isya 18°, ihtiyat 2 menit', 20, 18,
      ihtiyat: 2),
  jakim('JAKIM (Malaysia)', 'Subuh 20°, Isya 18°', 20, 18, ihtiyat: 1),
  muis('MUIS (Singapura)', 'Subuh 20°, Isya 18°', 20, 18, ihtiyat: 1),
  mwl('Muslim World League', 'Subuh 18°, Isya 17°', 18, 17),
  ummAlQura('Umm al-Qura (Makkah)', 'Subuh 18,5°, Isya 90 menit setelah Maghrib',
      18.5, 0,
      ishaMinutes: 90),
  egypt('Mesir (Egyptian General Authority)', 'Subuh 19,5°, Isya 17,5°', 19.5,
      17.5),
  karachi('Karachi', 'Subuh 18°, Isya 18°', 18, 18),
  isna('ISNA (Amerika Utara)', 'Subuh 15°, Isya 15°', 15, 15);

  const PrayerMethod(this.label, this.description, this.fajrAngle,
      this.ishaAngle,
      {this.ishaMinutes, this.ihtiyat = 0});

  final String label;
  final String description;
  final double fajrAngle;
  final double ishaAngle;

  /// Isya = Maghrib + menit ini (bila diisi, sudut Isya diabaikan).
  final int? ishaMinutes;

  /// Menit kehati-hatian: ditambahkan ke waktu sholat, dikurangkan dari
  /// syuruq (terbit).
  final int ihtiyat;

  static PrayerMethod parse(String? v) =>
      PrayerMethod.values.asNameMap()[v] ?? PrayerMethod.kemenag;
}

/// Mazhab untuk waktu Ashar.
enum AsrMadhab {
  syafii('Jumhur (Syafi\'i, Maliki, Hanbali)', 1),
  hanafi('Hanafi', 2);

  const AsrMadhab(this.label, this.shadowFactor);
  final String label;
  final int shadowFactor;

  static AsrMadhab parse(String? v) =>
      AsrMadhab.values.asNameMap()[v] ?? AsrMadhab.syafii;
}

/// Waktu-waktu dalam satu hari.
enum PrayerTime {
  imsak('Imsak', isFard: false),
  subuh('Subuh'),
  syuruq('Syuruq', isFard: false),
  dzuhur('Dzuhur'),
  ashar('Ashar'),
  maghrib('Maghrib'),
  isya('Isya'),
  sepertigaMalam('Sepertiga malam', isFard: false);

  const PrayerTime(this.label, {this.isFard = true});
  final String label;

  /// Sholat wajib (adzan). Lainnya: pengingat (imsak, syuruq, tahajud).
  final bool isFard;

  static const fard = [subuh, dzuhur, ashar, maghrib, isya];
}

/// Jadwal satu tanggal. [sepertigaMalam] = awal sepertiga malam terakhir
/// pada malam setelah Maghrib tanggal ini (jatuh dini hari tanggal berikut).
class PrayerDay {
  const PrayerDay(this.date, this.times);

  final DateTime date;
  final Map<PrayerTime, DateTime> times;

  DateTime operator [](PrayerTime p) => times[p]!;
}

class PrayerCalculator {
  const PrayerCalculator({
    required this.latitude,
    required this.longitude,
    this.method = PrayerMethod.kemenag,
    this.madhab = AsrMadhab.syafii,
    this.imsakMinutes = 10,
  });

  final double latitude;
  final double longitude;
  final PrayerMethod method;
  final AsrMadhab madhab;

  /// Imsak = Subuh − menit ini.
  final int imsakMinutes;

  /// Jadwal tanggal [date] dalam zona waktu perangkat.
  PrayerDay day(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final raw = _rawTimes(d);
    final next = _rawTimes(d.add(const Duration(days: 1)));
    final i = method.ihtiyat;

    DateTime at(DateTime base, double hours, {int add = 0, bool up = true}) {
      final t = base.add(Duration(seconds: (hours * 3600).round()))
          .add(Duration(minutes: add));
      // Dibulatkan ke menit: waktu sholat ke atas, syuruq ke bawah.
      final floor = DateTime(t.year, t.month, t.day, t.hour, t.minute);
      return up && t.isAfter(floor) ? floor.add(const Duration(minutes: 1)) : floor;
    }

    final subuh = at(d, raw.fajr, add: i);
    final maghrib = at(d, raw.sunset, add: i);
    final isha = method.ishaMinutes != null
        ? maghrib.add(Duration(minutes: method.ishaMinutes!))
        : at(d, raw.isha, add: i);
    final nextDay = d.add(const Duration(days: 1));
    final nextSubuh = at(nextDay, next.fajr, add: i);
    final night = nextSubuh.difference(maghrib);
    final lastThird = maghrib.add(night * 2 ~/ 3);

    return PrayerDay(d, {
      PrayerTime.imsak: subuh.subtract(Duration(minutes: imsakMinutes)),
      PrayerTime.subuh: subuh,
      PrayerTime.syuruq: at(d, raw.sunrise, add: -i, up: false),
      PrayerTime.dzuhur: at(d, raw.dhuhr, add: i),
      PrayerTime.ashar: at(d, raw.asr, add: i),
      PrayerTime.maghrib: maghrib,
      PrayerTime.isya: isha,
      PrayerTime.sepertigaMalam: DateTime(lastThird.year, lastThird.month,
          lastThird.day, lastThird.hour, lastThird.minute),
    });
  }

  /// Jadwal satu bulan penuh.
  List<PrayerDay> month(int year, int month) => [
        for (var d = DateTime(year, month);
            d.month == month;
            d = DateTime(d.year, d.month, d.day + 1))
          day(d),
      ];

  /// Waktu berikutnya (setelah [now]) dari daftar [which].
  (PrayerTime, DateTime)? next(DateTime now,
      {Iterable<PrayerTime> which = PrayerTime.fard}) {
    for (var offset = 0; offset < 2; offset++) {
      final d = day(DateTime(now.year, now.month, now.day + offset));
      final candidates = [
        for (final p in which)
          if (d[p].isAfter(now)) (p, d[p]),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (candidates.isNotEmpty) return candidates.first;
    }
    return null;
  }

  // ---------- Astronomi ----------

  ({double fajr, double sunrise, double dhuhr, double asr, double sunset, double isha})
      _rawTimes(DateTime d) {
    // Jam lokal perangkat pada tanggal itu (mengikuti zona waktu perangkat).
    final tz = DateTime(d.year, d.month, d.day, 12).timeZoneOffset.inMinutes / 60;
    final jd = _julian(d.year, d.month, d.day) - longitude / (15 * 24);

    double mid(double t) => _fixHour(12 - _sun(jd + t).eqt);
    double angleTime(double angle, double t, {required bool ccw}) {
      final decl = _sun(jd + t).decl;
      final noon = mid(t);
      final cosT = (-_sin(angle) - _sin(decl) * _sin(latitude)) /
          (_cos(decl) * _cos(latitude));
      final tt = _acos(cosT.clamp(-1.0, 1.0)) / 15;
      return ccw ? noon - tt : noon + tt;
    }

    double asr(double t) {
      final decl = _sun(jd + t).decl;
      final a = -_atan(1 / (madhab.shadowFactor + _tan((latitude - decl).abs())));
      return angleTime(a, t, ccw: false);
    }

    var t = (fajr: 5.0, sunrise: 6.0, dhuhr: 12.0, asr: 13.0, sunset: 18.0, isha: 18.0);
    for (var iter = 0; iter < 2; iter++) {
      t = (
        fajr: angleTime(method.fajrAngle, t.fajr / 24, ccw: true),
        sunrise: angleTime(0.833, t.sunrise / 24, ccw: true),
        dhuhr: mid(t.dhuhr / 24),
        asr: asr(t.asr / 24),
        sunset: angleTime(0.833, t.sunset / 24, ccw: false),
        isha: angleTime(method.ishaAngle == 0 ? 18 : method.ishaAngle,
            t.isha / 24,
            ccw: false),
      );
    }
    final shift = tz - longitude / 15;
    return (
      fajr: t.fajr + shift,
      sunrise: t.sunrise + shift,
      dhuhr: t.dhuhr + shift,
      asr: t.asr + shift,
      sunset: t.sunset + shift,
      isha: t.isha + shift,
    );
  }

  static ({double decl, double eqt}) _sun(double jd) {
    final dd = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * dd);
    final q = _fixAngle(280.459 + 0.98564736 * dd);
    final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g));
    final e = 23.439 - 0.00000036 * dd;
    final ra = _atan2(_cos(e) * _sin(l), _cos(l)) / 15;
    return (decl: _asin(_sin(e) * _sin(l)), eqt: q / 15 - _fixHour(ra));
  }

  static double _julian(int y, int m, int d) {
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = y ~/ 100;
    final b = 2 - a + a ~/ 4;
    return (365.25 * (y + 4716)).floorToDouble() +
        (30.6001 * (m + 1)).floorToDouble() +
        d +
        b -
        1524.5;
  }
}

/// Arah kiblat (derajat dari utara searah jarum jam) dari suatu lokasi.
double qiblaBearing(double latitude, double longitude) {
  const kaabaLat = 21.4225, kaabaLng = 39.8262;
  final dLng = kaabaLng - longitude;
  final b = _atan2(_sin(dLng),
      _cos(latitude) * _tan(kaabaLat) - _sin(latitude) * _cos(dLng));
  return _fixAngle(b);
}

/// Tanggal Hijriah (kalender tabular; bisa selisih ±1 hari dari penetapan
/// resmi — gunakan [adjustDays] untuk menyesuaikan).
class HijriDate {
  const HijriDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const monthNames = [
    'Muharram', 'Safar', 'Rabiul Awal', 'Rabiul Akhir', 'Jumadil Awal',
    'Jumadil Akhir', 'Rajab', 'Syaban', 'Ramadhan', 'Syawal', 'Dzulqaidah',
    'Dzulhijjah',
  ];

  bool get isRamadan => month == 9;

  @override
  String toString() => '$day ${monthNames[month - 1]} $year H';

  factory HijriDate.fromGregorian(DateTime date, {int adjustDays = 0}) {
    final g = DateTime(date.year, date.month, date.day + adjustDays);
    final a = (14 - g.month) ~/ 12;
    final y = g.year + 4800 - a;
    final m = g.month + 12 * a - 3;
    final jdn = g.day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;
    var l = jdn - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final month = (24 * l) ~/ 709;
    final day = l - (709 * month) ~/ 24;
    return HijriDate(30 * n + j - 30, month, day);
  }
}

double _fixAngle(double a) => a - 360 * (a / 360).floorToDouble();
double _fixHour(double a) => a - 24 * (a / 24).floorToDouble();
double _sin(double d) => math.sin(d * math.pi / 180);
double _cos(double d) => math.cos(d * math.pi / 180);
double _tan(double d) => math.tan(d * math.pi / 180);
double _asin(double x) => math.asin(x) * 180 / math.pi;
double _acos(double x) => math.acos(x) * 180 / math.pi;
double _atan(double x) => math.atan(x) * 180 / math.pi;
double _atan2(double y, double x) => math.atan2(y, x) * 180 / math.pi;
