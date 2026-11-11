import 'package:flutter/material.dart';

import '../prayer/prayer_service.dart';
import '../push.dart';
import '../store.dart';
import 'announcements_screen.dart';
import 'account_screen.dart';
import 'bills_screen.dart';
import 'complaints_screen.dart';
import 'dashboard_screen.dart';
import 'prayer_screen.dart';
import 'residents_screen.dart';
import 'visitors_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  void _goTo(int i) => setState(() => _index = i);

  /// Pindah tab berdasarkan namanya (urutan tab bisa berubah, mis. tab
  /// Keluhan disembunyikan dari warga saat fiturnya dinonaktifkan).
  void _goToTab(String label) {
    final i = _tabs.indexWhere((t) => t.label == label);
    if (i >= 0) _goTo(i);
  }

  List<_Tab> _tabs = const [];

  @override
  void initState() {
    super.initState();
    PushService.instance.target.addListener(_onPushTarget);
    WidgetsBinding.instance.addObserver(this);
    // Aplikasi dibuka dari notifikasi sebelum layar ini tampil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPushTarget();
      _startPrayer();
    });
  }

  /// Muat pengaturan adzan akun ini; login pertama warga: tawarkan adzan.
  Future<void> _startPrayer() async {
    final key = store.accountKey;
    if (key == null) return;
    await PrayerService.instance.attach(key);
    if (mounted) await offerAdzanIfNeeded(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Aplikasi dibuka lagi: jadwal adzan diperpanjang beberapa hari ke depan.
    if (state == AppLifecycleState.resumed &&
        PrayerService.instance.settings.enabled) {
      PrayerService.instance.reschedule();
    }
  }

  @override
  void dispose() {
    PushService.instance.target.removeListener(_onPushTarget);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Notifikasi diketuk: buka tab Tagihan atau halaman Pengumuman.
  void _onPushTarget() {
    final t = PushService.instance.target.value;
    if (t == null || !mounted) return;
    PushService.instance.target.value = null;
    switch (t) {
      case PushTarget.bills:
        Navigator.of(context).popUntil((r) => r.isFirst);
        _goTo(1);
      case PushTarget.announcements:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AnnouncementsScreen()));
    }
  }

  // Ikut diperbarui setiap data di store berubah.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tabs = <_Tab>[
      _Tab('Beranda', Icons.home_outlined, Icons.home,
          DashboardScreen(onNavigate: _goToTab)),
      const _Tab('Tagihan', Icons.receipt_long_outlined, Icons.receipt_long,
          BillsScreen()),
      if (store.isAdmin || store.complaintsEnabled)
        const _Tab('Keluhan', Icons.report_problem_outlined,
            Icons.report_problem, ComplaintsScreen()),
      if (store.isAdmin)
        const _Tab(
            'Warga', Icons.people_outline, Icons.people, ResidentsScreen())
      else
        const _Tab('Tamu', Icons.badge_outlined, Icons.badge, VisitorsScreen()),
      const _Tab('Akun', Icons.person_outline, Icons.person, AccountScreen()),
    ];
    _tabs = tabs;
    if (_index >= tabs.length) _index = tabs.length - 1;

    return Scaffold(
      // Tarik layar ke bawah untuk memuat ulang data (semua tab).
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: IndexedStack(
          index: _index,
          // Hanya tab aktif yang ikut animasi Hero (FAB tiap tab berbagi tag
          // default sehingga bentrok saat membuka halaman baru).
          children: [
            for (var i = 0; i < tabs.length; i++)
              HeroMode(enabled: i == _index, child: tabs[i].page),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}
