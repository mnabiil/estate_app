import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'adzan_sounds.dart';
import 'prayer_times.dart';

/// Lokasi cadangan bila GPS belum diizinkan (Monas, Jakarta).
const fallbackLatitude = -6.1754;
const fallbackLongitude = 106.8272;

/// Pengaturan adzan & jadwal sholat milik satu akun di perangkat ini.
class PrayerSettings {
  /// Warga sudah menjawab tawaran mengaktifkan adzan (login pertama).
  bool decided = false;

  /// Notifikasi adzan aktif.
  bool enabled = false;
  PrayerMethod method = PrayerMethod.kemenag;
  AsrMadhab madhab = AsrMadhab.syafii;

  /// Waktu yang diberi notifikasi. Sholat wajib: adzan; imsak, syuruq,
  /// sepertiga malam: pengingat biasa.
  Set<PrayerTime> active = {...PrayerTime.fard};
  String soundId = initialAdzanSoundId;
  String subuhSoundId = initialAdzanSoundId;

  /// Pengingat sebelum waktu sholat wajib (0 = tidak ada).
  int reminderMinutes = 0;

  /// Koreksi tanggal Hijriah (−2..+2 hari).
  int hijriAdjust = 0;

  /// Lokasi GPS terakhir.
  double? latitude;
  double? longitude;
  DateTime? locationAt;

  bool get hasLocation => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'decided': decided,
        'enabled': enabled,
        'method': method.name,
        'madhab': madhab.name,
        'active': [for (final p in active) p.name],
        'soundId': soundId,
        'subuhSoundId': subuhSoundId,
        'reminderMinutes': reminderMinutes,
        'hijriAdjust': hijriAdjust,
        'latitude': latitude,
        'longitude': longitude,
        'locationAt': locationAt?.toIso8601String(),
      };

  static PrayerSettings fromJson(Map<String, dynamic> m) => PrayerSettings()
    ..decided = m['decided'] == true
    ..enabled = m['enabled'] == true
    ..method = PrayerMethod.parse(m['method'] as String?)
    ..madhab = AsrMadhab.parse(m['madhab'] as String?)
    ..active = {
      for (final v in (m['active'] as List<dynamic>? ?? const []))
        if (PrayerTime.values.asNameMap()[v] case final p?) p,
    }
    ..soundId = m['soundId'] as String? ?? initialAdzanSoundId
    ..subuhSoundId = m['subuhSoundId'] as String? ?? initialAdzanSoundId
    ..reminderMinutes = (m['reminderMinutes'] as num?)?.toInt() ?? 0
    ..hijriAdjust = (m['hijriAdjust'] as num?)?.toInt() ?? 0
    ..latitude = (m['latitude'] as num?)?.toDouble()
    ..longitude = (m['longitude'] as num?)?.toDouble()
    ..locationAt = DateTime.tryParse(m['locationAt'] as String? ?? '');
}

/// Jadwal sholat (GPS pengguna) + notifikasi adzan terjadwal di perangkat.
/// Notifikasi dijadwalkan lokal (tanpa server), beberapa hari ke depan,
/// dan dijadwalkan ulang setiap aplikasi dibuka / pengaturan berubah.
class PrayerService extends ChangeNotifier {
  PrayerService._();
  static final instance = PrayerService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;
  String? _accountKey;
  PrayerSettings settings = PrayerSettings();

  /// Penyimpanan cadangan (tes / plugin tidak tersedia).
  static final Map<String, String> _memory = {};

  /// Notifikasi lokal hanya di Android & iOS (bukan tes / web / desktop).
  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  bool get attached => _accountKey != null;

  PrayerCalculator get calculator => PrayerCalculator(
        latitude: settings.latitude ?? fallbackLatitude,
        longitude: settings.longitude ?? fallbackLongitude,
        method: settings.method,
        madhab: settings.madhab,
      );

  PrayerDay today([DateTime? now]) => calculator.day(now ?? DateTime.now());

  HijriDate hijri([DateTime? date]) => HijriDate.fromGregorian(
      date ?? DateTime.now(),
      adjustDays: settings.hijriAdjust);

  String get _prefsKey => 'prayer.$_accountKey';

  /// Muat pengaturan akun (dipanggil setelah login).
  Future<void> attach(String accountKey) async {
    if (_accountKey == accountKey) return;
    _accountKey = accountKey;
    settings = PrayerSettings();
    String? raw;
    try {
      raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
    } catch (_) {
      raw = _memory[_prefsKey];
    }
    if (raw != null) {
      try {
        settings = PrayerSettings.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    notifyListeners();
    if (settings.enabled) {
      // Perbarui lokasi diam-diam (tanpa meminta izin lagi) lalu jadwalkan.
      await updateLocation(request: false);
      await reschedule();
    }
  }

  /// Logout: hentikan notifikasi adzan akun ini di perangkat.
  Future<void> detach() async {
    _accountKey = null;
    settings = PrayerSettings();
    await _cancelScheduled();
    notifyListeners();
  }

  Future<void> save() async {
    if (_accountKey == null) return;
    final raw = jsonEncode(settings.toJson());
    _memory[_prefsKey] = raw;
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, raw);
    } catch (_) {}
    notifyListeners();
  }

  /// Ubah pengaturan, simpan, lalu jadwalkan ulang notifikasi.
  Future<void> update(void Function(PrayerSettings s) change) async {
    change(settings);
    await save();
    await reschedule();
  }

  /// Aktifkan/nonaktifkan adzan (juga menandai pertanyaan login pertama
  /// sudah dijawab). Saat diaktifkan: minta izin notifikasi & lokasi.
  Future<void> setEnabled(bool enabled) async {
    settings
      ..decided = true
      ..enabled = enabled;
    await save();
    if (enabled) {
      await requestPermissions();
      await updateLocation();
    }
    await reschedule();
  }

  /// Ambil lokasi GPS. [request]: minta izin bila belum. Mengembalikan pesan
  /// kesalahan, atau null bila berhasil.
  Future<String?> updateLocation({bool request = true}) async {
    if (!supported) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'GPS / layanan lokasi sedang mati.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && request) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return 'Izin lokasi tidak diberikan. Jadwal memakai lokasi '
            '${settings.hasLocation ? 'terakhir' : 'Jakarta'}.';
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        // Sinyal GPS lemah: pakai lokasi terakhir yang diketahui perangkat.
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        return 'Lokasi belum didapat. Coba lagi di tempat terbuka.';
      }
      settings
        ..latitude = pos.latitude
        ..longitude = pos.longitude
        ..locationAt = DateTime.now();
      await save();
      return null;
    } catch (e) {
      return 'Lokasi belum didapat. Coba lagi di tempat terbuka.';
    }
  }

  Future<void> _init() async {
    if (_pluginReady || !supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _pluginReady = true;
    await _installIosSounds();
  }

  /// iOS memutar suara notifikasi dari Library/Sounds milik aplikasi: salin
  /// potongan adzan dari aset ke sana (sekali; tidak perlu ubah proyek Xcode).
  Future<void> _installIosSounds() async {
    if (!Platform.isIOS) return;
    try {
      final dir = Directory('${(await getLibraryDirectory()).path}/Sounds');
      await dir.create(recursive: true);
      for (final s in adzanSounds) {
        final name = s.iosFile;
        if (name == null) continue;
        final file = File('${dir.path}/$name');
        if (await file.exists()) continue;
        final data = await rootBundle.load('assets/adzan/$name');
        await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    } catch (e) {
      debugPrint('Salin suara adzan iOS: $e');
    }
  }

  /// Izin notifikasi (Android 13+/iOS) & alarm tepat waktu (Android 12+).
  Future<void> requestPermissions() async {
    if (!supported) return;
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      if (await android?.canScheduleExactNotifications() == false) {
        await android?.requestExactAlarmsPermission();
      }
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true, badge: false);
    } catch (e) {
      debugPrint('Izin notifikasi adzan: $e');
    }
  }

  /// Alarm tepat waktu diizinkan (Android 12+). null = tidak relevan.
  Future<bool?> exactAlarmAllowed() async {
    if (!supported || !Platform.isAndroid) return null;
    await _init();
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
  }

  // ---------- Penjadwalan ----------

  static const _idBase = 7000;
  static const _idsPerDay = 20;

  /// Android: 7 hari; iOS dibatasi 64 notifikasi tertunda → 3 hari.
  static int get _days => supported && Platform.isIOS ? 3 : 7;

  int _id(int day, PrayerTime p, {bool reminder = false}) =>
      _idBase + day * _idsPerDay + p.index * 2 + (reminder ? 1 : 0);

  Future<void> _cancelScheduled() async {
    if (!supported) return;
    try {
      await _init();
      for (var i = 0; i < 7 * _idsPerDay; i++) {
        await _plugin.cancel(id: _idBase + i);
      }
    } catch (e) {
      debugPrint('Batal notifikasi adzan: $e');
    }
  }

  NotificationDetails _details(PrayerTime p, {bool reminder = false}) {
    final isAdzan = p.isFard && !reminder;
    final sound = adzanSoundById(
        p == PrayerTime.subuh ? settings.subuhSoundId : settings.soundId);
    final channelId = isAdzan ? 'adzan_${sound.id}' : 'pengingat_sholat';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        isAdzan ? 'Adzan · ${sound.label}' : 'Pengingat sholat',
        channelDescription: isAdzan
            ? 'Notifikasi masuk waktu sholat'
            : 'Pengingat imsak, syuruq, sepertiga malam & sebelum sholat',
        importance: isAdzan ? Importance.max : Importance.high,
        priority: isAdzan ? Priority.max : Priority.high,
        category: AndroidNotificationCategory.reminder,
        sound: isAdzan && sound.androidRaw != null
            ? RawResourceAndroidNotificationSound(sound.androidRaw!)
            : null,
      ),
      iOS: DarwinNotificationDetails(
        sound: isAdzan ? sound.iosFile : null,
        presentSound: true,
      ),
    );
  }

  /// Jadwalkan ulang semua notifikasi adzan beberapa hari ke depan.
  Future<void> reschedule() async {
    if (!supported) return;
    try {
      await _cancelScheduled();
      if (!settings.enabled || settings.active.isEmpty) return;
      final exact = await exactAlarmAllowed() ?? true;
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final now = DateTime.now();
      final calc = calculator;
      for (var day = 0; day < _days; day++) {
        final d = calc.day(DateTime(now.year, now.month, now.day + day));
        for (final p in settings.active) {
          final t = d[p];
          if (t.isAfter(now)) {
            await _plugin.zonedSchedule(
              id: _id(day, p),
              scheduledDate: tz.TZDateTime.from(t.toUtc(), tz.UTC),
              notificationDetails: _details(p),
              androidScheduleMode: mode,
              title: p.isFard ? 'Waktu ${p.label}' : p.label,
              body: _body(p, t),
              payload: 'prayer',
            );
          }
          final r = settings.reminderMinutes;
          final before = t.subtract(Duration(minutes: r));
          if (p.isFard && r > 0 && before.isAfter(now)) {
            await _plugin.zonedSchedule(
              id: _id(day, p, reminder: true),
              scheduledDate: tz.TZDateTime.from(before.toUtc(), tz.UTC),
              notificationDetails: _details(p, reminder: true),
              androidScheduleMode: mode,
              title: '$r menit lagi ${p.label}',
              body: 'Waktu ${p.label} pukul ${_hm(t)}.',
              payload: 'prayer',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Jadwal adzan gagal: $e');
    }
  }

  String _body(PrayerTime p, DateTime t) => switch (p) {
        PrayerTime.imsak => 'Imsak pukul ${_hm(t)}. Segera akhiri sahur.',
        PrayerTime.syuruq => 'Matahari terbit pukul ${_hm(t)}. Waktu Subuh berakhir.',
        PrayerTime.sepertigaMalam =>
          'Sepertiga malam terakhir dimulai. Waktu utama sholat tahajud.',
        _ => 'Telah masuk waktu sholat ${p.label} (${_hm(t)}).',
      };

  /// Bunyikan contoh suara adzan sekarang.
  Future<void> testSound(String soundId, {bool subuh = false}) async {
    if (!supported) return;
    await _init();
    await requestPermissions();
    final saved = (settings.soundId, settings.subuhSoundId);
    settings
      ..soundId = soundId
      ..subuhSoundId = soundId;
    final details = _details(subuh ? PrayerTime.subuh : PrayerTime.dzuhur);
    settings
      ..soundId = saved.$1
      ..subuhSoundId = saved.$2;
    await _plugin.show(
      id: _idBase - 1,
      title: 'Contoh suara adzan',
      body: adzanSoundById(soundId).label,
      notificationDetails: details,
    );
  }
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
