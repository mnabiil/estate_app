import 'package:flutter/material.dart';

import '../push.dart';
import '../store.dart';
import 'announcements_screen.dart';
import 'account_screen.dart';
import 'bills_screen.dart';
import 'complaints_screen.dart';
import 'dashboard_screen.dart';
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

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _goTo(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    PushService.instance.target.addListener(_onPushTarget);
    // Aplikasi dibuka dari notifikasi sebelum layar ini tampil.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPushTarget());
  }

  @override
  void dispose() {
    PushService.instance.target.removeListener(_onPushTarget);
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

  @override
  Widget build(BuildContext context) {
    final tabs = <_Tab>[
      _Tab('Beranda', Icons.home_outlined, Icons.home,
          DashboardScreen(onNavigate: _goTo)),
      const _Tab('Tagihan', Icons.receipt_long_outlined, Icons.receipt_long,
          BillsScreen()),
      const _Tab('Keluhan', Icons.report_problem_outlined, Icons.report_problem,
          ComplaintsScreen()),
      if (store.isAdmin)
        const _Tab(
            'Warga', Icons.people_outline, Icons.people, ResidentsScreen())
      else
        const _Tab('Tamu', Icons.badge_outlined, Icons.badge, VisitorsScreen()),
      const _Tab('Akun', Icons.person_outline, Icons.person, AccountScreen()),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (final t in tabs) t.page],
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
