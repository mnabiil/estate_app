import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../utils.dart';
import 'announcements_screen.dart';
import 'visitors_screen.dart';

/// Indeks tab di HomeShell.
const _tabBills = 1;
const _tabComplaints = 2;
const _tabFourth = 3; // Warga (pengelola) atau Tamu (warga)

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final user = store.currentUser!;
        final now = DateTime.now();
        final thisMonth = DateTime(now.year, now.month);
        final todayVisitors =
            store.visitors.where((v) => isSameDay(v.visitDate, now));

        final List<_Stat> stats;
        if (store.isAdmin) {
          final unpaidThisMonth = store.bills.where((b) =>
              b.period == thisMonth && b.status == BillStatus.belumBayar);
          stats = [
            _Stat(Icons.people, '${store.residents.length}', 'Jumlah warga',
                () => onNavigate(_tabFourth)),
            _Stat(Icons.receipt_long, '${unpaidThisMonth.length} rumah',
                'Belum bayar IPL bulan ini', () => onNavigate(_tabBills)),
            _Stat(
                Icons.report_problem,
                '${store.complaints.where((c) => c.status != ComplaintStatus.selesai).length}',
                'Keluhan aktif',
                () => onNavigate(_tabComplaints)),
            _Stat(Icons.badge, '${todayVisitors.length}', 'Tamu hari ini',
                () => _push(context, const VisitorsScreen())),
          ];
        } else {
          final rid = user.residentId!;
          stats = [
            _Stat(Icons.receipt_long, formatRupiah(store.unpaidTotal(rid)),
                'Tagihan belum dibayar', () => onNavigate(_tabBills)),
            _Stat(
                Icons.report_problem,
                '${store.complaints.where((c) => c.residentId == rid && c.status != ComplaintStatus.selesai).length}',
                'Keluhan aktif',
                () => onNavigate(_tabComplaints)),
            _Stat(
                Icons.badge,
                '${todayVisitors.where((v) => v.residentId == rid).length}',
                'Tamu hari ini',
                () => onNavigate(_tabFourth)),
            _Stat(Icons.campaign, '${store.announcements.length}', 'Pengumuman',
                () => _push(context, const AnnouncementsScreen())),
          ];
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Griya Kita'),
            actions: [
              IconButton(
                tooltip: 'Pengumuman',
                icon: const Icon(Icons.campaign_outlined),
                onPressed: () => _push(context, const AnnouncementsScreen()),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Halo, ${user.name}',
                          style: theme.textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        store.isAdmin
                            ? 'Pengelola $estateName'
                            : 'Rumah ${store.currentResident?.houseNo} · $estateName',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [for (final s in stats) _StatCard(s)],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Pengumuman terbaru',
                        style: theme.textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: () =>
                        _push(context, const AnnouncementsScreen()),
                    child: const Text('Lihat semua'),
                  ),
                ],
              ),
              for (final a in store.announcements.take(2))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(a.title),
                    subtitle: Text(a.body,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat {
  const _Stat(this.icon, this.value, this.label, this.onTap);
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.stat);
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stat.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(stat.icon, color: theme.colorScheme.primary),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(stat.value,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Text(stat.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
