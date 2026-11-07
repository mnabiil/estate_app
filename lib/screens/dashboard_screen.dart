import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../utils.dart';
import 'announcements_screen.dart';
import 'master_data_screen.dart';
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

        final hero = stats.first;
        final rest = stats.skip(1).toList();

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                // Header: avatar, nama perumahan, tombol pengumuman.
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: Text(
                        user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(30),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          // Pengelola dengan beberapa perumahan: ketuk untuk
                          // berpindah perumahan.
                          onTap: store.isAdmin && store.estates.length > 1
                              ? () => showEstateSwitcher(context)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    size: 18, color: scheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    estateName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                                if (store.isAdmin && store.estates.length > 1)
                                  Icon(Icons.unfold_more,
                                      size: 18, color: scheme.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Pengumuman',
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerHighest,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.notifications_none_rounded),
                      onPressed: () =>
                          _push(context, const AnnouncementsScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                TwoToneHeading('Halo,', user.name),
                const SizedBox(height: 6),
                Text(
                  store.isAdmin
                      ? 'Pengelola $estateName'
                      : 'Rumah ${store.currentResident?.houseNo} · $estateName',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                _HeroCard(stat: hero, isAdmin: store.isAdmin),
                const SizedBox(height: 28),
                Text('Ringkasan',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontFamily: fontDisplay)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < rest.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _StatCard(rest[i])),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text('Pengumuman terbaru',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontFamily: fontDisplay)),
                    ),
                    TextButton(
                      onPressed: () =>
                          _push(context, const AnnouncementsScreen()),
                      child: const Text('Lihat semua'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final a in store.announcements.take(2))
                  Card(
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.campaign_outlined,
                            color: scheme.primary),
                      ),
                      title: Text(a.title),
                      subtitle: Text(a.body,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () =>
                          _push(context, const AnnouncementsScreen()),
                    ),
                  ),
              ],
            ),
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

/// Kartu utama bergradasi, seperti kartu pembayaran di desain.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.stat, required this.isAdmin});

  final _Stat stat;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3EA05E).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusCard),
          onTap: stat.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(stat.icon, color: Colors.white),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isAdmin ? 'Pengelola' : 'Warga',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  stat.label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    stat.value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFamily: fontBody,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Lihat detail',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 18, color: Colors.white),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.stat);
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stat.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(stat.icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(stat.value,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 34,
                child: Text(stat.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
