import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models.dart';
import '../prayer/adzan_sounds.dart';
import '../prayer/prayer_service.dart';
import '../prayer/prayer_times.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets.dart';

PrayerService get _prayer => PrayerService.instance;

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _countdown(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h > 0) return '$h jam $m menit lagi';
  if (m > 0) return '$m menit lagi';
  return 'sebentar lagi';
}

/// Rebuild tiap 30 detik (hitung mundur) dan saat pengaturan berubah.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.builder});
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _prayer,
        builder: (context, _) => widget.builder(context, DateTime.now()),
      );
}

/// Login pertama warga: tawarkan mengaktifkan notifikasi adzan.
Future<void> offerAdzanIfNeeded(BuildContext context) async {
  if (!PrayerService.supported ||
      store.isAdmin ||
      _prayer.settings.decided ||
      !_prayer.attached) {
    return;
  }
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.mosque_outlined),
      title: const Text('Aktifkan notifikasi adzan?'),
      content: const Text(
          'Amani Living bisa membunyikan adzan setiap masuk waktu sholat, '
          'sesuai lokasi GPS Anda. Anda bisa memilih waktu sholat, suara '
          'adzan, dan metode perhitungan di menu Jadwal Sholat.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti saja')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, aktifkan')),
      ],
    ),
  );
  if (yes == null) return;
  if (yes) {
    await _prayer.setEnabled(true);
    if (context.mounted) {
      showSnack(context, 'Adzan aktif. Atur di menu Jadwal Sholat.');
    }
  } else {
    _prayer.settings.decided = true;
    await _prayer.save();
  }
}

/// Kartu Beranda: sholat berikutnya + hitung mundur + 5 waktu hari ini.
class NextPrayerCard extends StatelessWidget {
  const NextPrayerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Ticker(builder: (context, now) {
      final calc = _prayer.calculator;
      final next = calc.next(now);
      final today = calc.day(now);
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrayerScreen())),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mosque_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        next == null
                            ? 'Jadwal sholat'
                            : '${next.$1.label} ${hm(next.$2)}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (next != null)
                      Text(_countdown(next.$2.difference(now)),
                          style: theme.textTheme.bodySmall),
                    Icon(
                        _prayer.settings.enabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        size: 18,
                        color: scheme.outline),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final p in PrayerTime.fard)
                      Column(
                        children: [
                          Text(p.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: next?.$1 == p
                                      ? scheme.primary
                                      : scheme.outline)),
                          Text(hm(today[p]),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: next?.$1 == p
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Jadwal sholat hari ini, lokasi, tanggal Hijriah, info masjid, menu.
class PrayerScreen extends StatelessWidget {
  const PrayerScreen({super.key});

  Future<void> _updateLocation(BuildContext context) async {
    final err = await runAction(
        context, _prayer.updateLocation().then((e) async {
      await _prayer.reschedule();
      return e ?? '';
    }), refresh: false);
    if (err == null || !context.mounted) return;
    showSnack(context, err.isEmpty ? 'Lokasi diperbarui' : err);
  }

  Future<void> _toggle(BuildContext context, PrayerTime p) async {
    final on = !_prayer.settings.active.contains(p);
    if (on && !_prayer.settings.enabled) {
      final ok = await confirmSave(context,
          title: 'Aktifkan notifikasi adzan?',
          details: {'Waktu': p.label},
          note: 'Notifikasi adzan akan aktif untuk waktu yang dipilih.',
          action: 'Ya, aktifkan');
      if (!ok || !context.mounted) return;
      _prayer.settings.active.add(p);
      await _prayer.setEnabled(true);
      return;
    }
    await _prayer.update((s) => on ? s.active.add(p) : s.active.remove(p));
    if (context.mounted) {
      showSnack(context,
          '${p.isFard ? 'Adzan' : 'Pengingat'} ${p.label} ${on ? 'aktif' : 'dimatikan'}');
    }
  }

  Future<void> _editMosque(BuildContext context) async {
    final name = TextEditingController(text: store.mosqueName);
    final info = TextEditingController(text: store.mosqueInfo);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Masjid / musholla perumahan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Nama')),
              TextField(
                controller: info,
                maxLength: 1000,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                    labelText: 'Info',
                    hintText: 'Jadwal Jumat, kajian, imam/khatib, dll.',
                    alignLabelWithHint: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final confirmed = await confirmSave(context,
        title: 'Simpan info masjid?',
        details: {
          'Perumahan': estateName,
          'Nama': name.text,
          'Info': info.text,
        });
    if (!confirmed || !context.mounted) return;
    await runAction(context, store.saveMosqueInfo(name.text, info.text),
        success: 'Info masjid disimpan');
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _Ticker(builder: (context, now) {
        final s = _prayer.settings;
        final calc = _prayer.calculator;
        final today = calc.day(now);
        final next = calc.next(now, which: PrayerTime.values);
        final hijri = _prayer.hijri(now);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Jadwal Sholat'),
            actions: [
              IconButton(
                tooltip: 'Pengaturan adzan',
                icon: const Icon(Icons.tune),
                onPressed: () => _open(context, const PrayerSettingsScreen()),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await _prayer.updateLocation(request: false);
              await _prayer.reschedule();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$hijri · ${formatDate(now)}',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        if (next != null) ...[
                          Text('${next.$1.label} · ${hm(next.$2)}',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text(_countdown(next.$2.difference(now))),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 16, color: scheme.onPrimaryContainer),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                s.hasLocation
                                    ? 'Lokasi GPS ${s.latitude!.toStringAsFixed(3)}, '
                                        '${s.longitude!.toStringAsFixed(3)}'
                                    : 'Lokasi bawaan: Jakarta (GPS belum aktif)',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _updateLocation(context),
                              child: const Text('Perbarui GPS'),
                            ),
                          ],
                        ),
                        Text('Metode: ${s.method.label}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (hijri.isRamadan)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.nightlight_round),
                      title: Text('Ramadhan · Imsak ${hm(today[PrayerTime.imsak])} · '
                          'Berbuka ${hm(today[PrayerTime.maghrib])}'),
                      subtitle: const Text('Lihat jadwal imsakiyah sebulan'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context,
                          const MonthlyScheduleScreen(imsakiyah: true)),
                    ),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final p in PrayerTime.values)
                        ListTile(
                          dense: !p.isFard,
                          selected: next?.$1 == p,
                          leading: Icon(_iconOf(p)),
                          title: Text(p.label),
                          subtitle: p == PrayerTime.sepertigaMalam
                              ? const Text('Malam ini · waktu utama tahajud')
                              : p.isFard
                                  ? null
                                  : Text(p == PrayerTime.imsak
                                      ? 'Akhir sahur'
                                      : 'Matahari terbit · akhir Subuh'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(hm(today[p]),
                                  style: theme.textTheme.titleMedium),
                              IconButton(
                                tooltip: s.active.contains(p) && s.enabled
                                    ? 'Matikan notifikasi'
                                    : 'Aktifkan notifikasi',
                                icon: Icon(
                                  s.active.contains(p) && s.enabled
                                      ? (p.isFard
                                          ? Icons.volume_up
                                          : Icons.notifications_active)
                                      : Icons.notifications_off_outlined,
                                  color: s.active.contains(p) && s.enabled
                                      ? scheme.primary
                                      : scheme.outline,
                                ),
                                onPressed: () => _toggle(context, p),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (store.mosqueName.isNotEmpty ||
                    store.can(AdminPermission.masterData))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.mosque),
                      title: Text(store.mosqueName.isEmpty
                          ? 'Info masjid / musholla belum diisi'
                          : store.mosqueName),
                      subtitle:
                          store.mosqueInfo.isEmpty ? null : Text(store.mosqueInfo),
                      trailing: store.can(AdminPermission.masterData)
                          ? IconButton(
                              tooltip: 'Ubah info masjid',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editMosque(context),
                            )
                          : null,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _open(context, const MonthlyScheduleScreen()),
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Jadwal bulanan'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _open(context, const QiblaScreen()),
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Arah kiblat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

IconData _iconOf(PrayerTime p) => switch (p) {
      PrayerTime.imsak => Icons.restaurant_outlined,
      PrayerTime.subuh => Icons.wb_twilight,
      PrayerTime.syuruq => Icons.wb_sunny_outlined,
      PrayerTime.dzuhur => Icons.light_mode,
      PrayerTime.ashar => Icons.light_mode_outlined,
      PrayerTime.maghrib => Icons.wb_twilight_outlined,
      PrayerTime.isya => Icons.nights_stay_outlined,
      PrayerTime.sepertigaMalam => Icons.bedtime_outlined,
    };

/// Jadwal satu bulan (juga imsakiyah Ramadhan).
class MonthlyScheduleScreen extends StatefulWidget {
  const MonthlyScheduleScreen({super.key, this.imsakiyah = false});
  final bool imsakiyah;

  @override
  State<MonthlyScheduleScreen> createState() => _MonthlyScheduleScreenState();
}

class _MonthlyScheduleScreenState extends State<MonthlyScheduleScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _prayer.calculator.month(_month.year, _month.month);
    final today = dateOnly(DateTime.now());
    const cols = PrayerTime.values;
    final head = theme.textTheme.labelSmall
        ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.imsakiyah ? 'Imsakiyah' : 'Jadwal bulanan')),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text(formatMonth(_month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DataTable(
                  columnSpacing: 14,
                  headingRowHeight: 40,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 44,
                  columns: [
                    DataColumn(label: Text('Tgl', style: head)),
                    for (final p in cols)
                      DataColumn(
                          label: Text(
                              p == PrayerTime.sepertigaMalam ? '⅓ Malam' : p.label,
                              style: head)),
                  ],
                  rows: [
                    for (final d in days)
                      DataRow(
                        selected: d.date == today,
                        cells: [
                          DataCell(Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${d.date.day}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '${_prayer.hijri(d.date).day} '
                                  '${HijriDate.monthNames[_prayer.hijri(d.date).month - 1].substring(0, 3)}',
                                  style: theme.textTheme.labelSmall),
                            ],
                          )),
                          for (final p in cols)
                            DataCell(Text(hm(d[p]),
                                style: widget.imsakiyah &&
                                        (p == PrayerTime.imsak ||
                                            p == PrayerTime.maghrib)
                                    ? const TextStyle(fontWeight: FontWeight.bold)
                                    : null)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompas arah kiblat (magnetometer). Letakkan HP mendatar.
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  StreamSubscription<MagnetometerEvent>? _sub;
  double? _heading;
  bool _sensorError = false;

  @override
  void initState() {
    super.initState();
    try {
      _sub = magnetometerEventStream().listen((e) {
        // HP mendatar: arah atas HP terhadap utara magnetik.
        final h = math.atan2(-e.x, e.y) * 180 / math.pi;
        final heading = (h + 360) % 360;
        // Haluskan agar jarum tidak bergetar.
        final prev = _heading;
        setState(() => _heading = prev == null
            ? heading
            : (prev + _angleDiff(heading, prev) * 0.2 + 360) % 360);
      }, onError: (_) => setState(() => _sensorError = true));
    } catch (_) {
      _sensorError = true;
    }
  }

  static double _angleDiff(double a, double b) => ((a - b + 540) % 360) - 180;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _prayer.settings;
    final lat = s.latitude ?? fallbackLatitude;
    final lng = s.longitude ?? fallbackLongitude;
    final qibla = qiblaBearing(lat, lng);
    final heading = _heading;
    final relative = heading == null ? qibla : (qibla - heading + 360) % 360;
    final aligned =
        heading != null && _angleDiff(qibla, heading).abs() < 5;
    return Scaffold(
      appBar: AppBar(title: const Text('Arah kiblat')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('${qibla.toStringAsFixed(1)}° dari utara',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            s.hasLocation ? 'Dari lokasi GPS Anda' : 'Dari Jakarta (GPS belum aktif)',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -(heading ?? 0) * math.pi / 180,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _DialPainter(theme.colorScheme),
                  ),
                ),
                Transform.rotate(
                  angle: relative * math.pi / 180,
                  child: Icon(Icons.navigation,
                      size: 120,
                      color: aligned
                          ? Colors.green.shade600
                          : theme.colorScheme.primary),
                ),
                const Icon(Icons.mosque, size: 28),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _sensorError || heading == null
                ? 'Sensor kompas tidak tersedia. Gunakan sudut di atas dengan '
                    'kompas lain (searah jarum jam dari utara).'
                : aligned
                    ? 'Sudah menghadap kiblat'
                    : 'Letakkan HP mendatar dan putar sampai panah berwarna hijau. '
                        'Jauhkan dari benda logam/magnet; bila melenceng, gerakkan HP '
                        'membentuk angka 8 untuk kalibrasi.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.scheme);
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.outlineVariant);
    for (var deg = 0; deg < 360; deg += 30) {
      final a = deg * math.pi / 180;
      final p1 = c + Offset(math.sin(a), -math.cos(a)) * (r - 10);
      final p2 = c + Offset(math.sin(a), -math.cos(a)) * r;
      canvas.drawLine(p1, p2, Paint()..color = scheme.outline..strokeWidth = 2);
    }
    const labels = {'U': 0, 'T': 90, 'S': 180, 'B': 270};
    labels.forEach((t, deg) {
      final a = deg * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(
                color: t == 'U' ? Colors.red : scheme.onSurface,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = c + Offset(math.sin(a), -math.cos(a)) * (r - 26);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    });
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.scheme != scheme;
}

/// Pengaturan adzan: aktif/tidak, waktu, suara, pengingat, metode.
class PrayerSettingsScreen extends StatelessWidget {
  const PrayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _prayer,
      builder: (context, _) {
        final s = _prayer.settings;
        Widget soundPicker(String label, String value, bool subuh,
                void Function(String) onChanged) =>
            ListTile(
              title: Text(label),
              subtitle: Text(adzanSoundById(value).label),
              trailing: IconButton(
                tooltip: 'Coba suara',
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () => _prayer.testSound(value, subuh: subuh),
              ),
              onTap: () async {
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final a in adzanSounds
                            .where((a) => subuh || !a.subuhOnly))
                          ListTile(
                            leading: Icon(a.id == value
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                            title: Text(a.label),
                            trailing: IconButton(
                              tooltip: 'Coba',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () =>
                                  _prayer.testSound(a.id, subuh: subuh),
                            ),
                            onTap: () => Navigator.pop(ctx, a.id),
                          ),
                      ],
                    ),
                  ),
                );
                if (picked != null) onChanged(picked);
              },
            );

        return Scaffold(
          appBar: AppBar(title: const Text('Pengaturan adzan')),
          body: ListView(
            children: [
              SwitchListTile(
                value: s.enabled,
                onChanged: (v) => _prayer.setEnabled(v),
                title: const Text('Notifikasi adzan'),
                subtitle: Text(s.enabled
                    ? 'Aktif di perangkat ini'
                    : 'Mati · tidak ada adzan / pengingat'),
              ),
              const Divider(),
              _Header('Adzan untuk waktu', theme),
              for (final p in PrayerTime.fard)
                CheckboxListTile(
                  value: s.active.contains(p),
                  onChanged: s.enabled
                      ? (v) => _prayer.update(
                          (x) => v == true ? x.active.add(p) : x.active.remove(p))
                      : null,
                  title: Text(p.label),
                ),
              _Header('Pengingat lain', theme),
              for (final p in const [
                PrayerTime.imsak,
                PrayerTime.syuruq,
                PrayerTime.sepertigaMalam
              ])
                CheckboxListTile(
                  value: s.active.contains(p),
                  onChanged: s.enabled
                      ? (v) => _prayer.update(
                          (x) => v == true ? x.active.add(p) : x.active.remove(p))
                      : null,
                  title: Text(p.label),
                  subtitle: Text(switch (p) {
                    PrayerTime.imsak => 'Akhir sahur (Subuh − 10 menit)',
                    PrayerTime.syuruq => 'Matahari terbit, akhir waktu Subuh',
                    _ => 'Awal sepertiga malam terakhir (tahajud)',
                  }),
                ),
              ListTile(
                title: const Text('Pengingat sebelum sholat'),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const [0, 5, 10, 15, 30])
                      ChoiceChip(
                        label: Text(m == 0 ? 'Tidak' : '$m menit'),
                        selected: s.reminderMinutes == m,
                        onSelected: s.enabled
                            ? (_) => _prayer.update((x) => x.reminderMinutes = m)
                            : null,
                      ),
                  ],
                ),
              ),
              const Divider(),
              _Header('Suara', theme),
              soundPicker('Suara adzan', s.soundId, false,
                  (v) => _prayer.update((x) => x.soundId = v)),
              soundPicker('Suara adzan Subuh', s.subuhSoundId, true,
                  (v) => _prayer.update((x) => x.subuhSoundId = v)),
              const Divider(),
              _Header('Perhitungan', theme),
              for (final m in PrayerMethod.values)
                ListTile(
                  leading: Icon(
                    s.method == m
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: s.method == m ? theme.colorScheme.primary : null,
                  ),
                  onTap: () => _prayer.update((x) => x.method = m),
                  title: Text(m.label),
                  subtitle: Text(m.description),
                ),
              ListTile(
                title: const Text('Waktu Ashar'),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    for (final m in AsrMadhab.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: s.madhab == m,
                        onSelected: (_) => _prayer.update((x) => x.madhab = m),
                      ),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Koreksi tanggal Hijriah'),
                subtitle: Text(_prayer.hijri().toString()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: s.hijriAdjust > -2
                          ? () => _prayer.update((x) => x.hijriAdjust--)
                          : null,
                    ),
                    Text('${s.hijriAdjust >= 0 ? '+' : ''}${s.hijriAdjust}'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: s.hijriAdjust < 2
                          ? () => _prayer.update((x) => x.hijriAdjust++)
                          : null,
                    ),
                  ],
                ),
              ),
              const Divider(),
              const _ExactAlarmTile(),
              const ListTile(
                leading: Icon(Icons.battery_alert_outlined),
                title: Text('Adzan telat atau tidak bunyi?'),
                subtitle: Text(
                    'Di beberapa HP (Xiaomi, Oppo, Vivo, Samsung), buka '
                    'Pengaturan → Aplikasi → Amani Living → Baterai → pilih '
                    '"Tanpa batasan", dan izinkan "Mulai otomatis". Suara adzan '
                    'mengikuti volume notifikasi. Di iPhone, suara adzan '
                    'maksimal 30 detik.'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, this.theme);
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary)),
      );
}

/// Android 12+: izin alarm tepat waktu agar adzan tidak terlambat.
class _ExactAlarmTile extends StatefulWidget {
  const _ExactAlarmTile();

  @override
  State<_ExactAlarmTile> createState() => _ExactAlarmTileState();
}

class _ExactAlarmTileState extends State<_ExactAlarmTile> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final v = await _prayer.exactAlarmAllowed();
    if (mounted) setState(() => _allowed = v);
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == null) return const SizedBox.shrink();
    return ListTile(
      leading: Icon(_allowed! ? Icons.alarm_on : Icons.alarm_off,
          color: _allowed! ? Colors.green.shade600 : Colors.orange.shade700),
      title: const Text('Alarm tepat waktu'),
      subtitle: Text(_allowed!
          ? 'Diizinkan · adzan berbunyi tepat waktu'
          : 'Belum diizinkan · adzan bisa terlambat beberapa menit'),
      trailing: _allowed!
          ? null
          : TextButton(
              onPressed: () async {
                await _prayer.requestPermissions();
                await _check();
                await _prayer.reschedule();
              },
              child: const Text('Izinkan'),
            ),
    );
  }
}
