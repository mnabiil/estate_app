import 'package:flutter/material.dart';

import '../store.dart';
import 'announcements_screen.dart';
import 'household_screen.dart';
import 'master_data_screen.dart';
import 'notification_settings_screen.dart';
import 'password_screen.dart';
import 'registrations_screen.dart';
import 'renovations_screen.dart';
import 'visitors_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = store.currentUser!;
    final resident = store.currentResident;
    final theme = Theme.of(context);

    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text(user.name[0], style: theme.textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user.name, style: theme.textTheme.titleLarge)),
          Center(
            child: Text(
              store.isAdmin
                  ? 'Pengelola · $estateName'
                  : user.isPrimary
                      ? 'Kepala keluarga · Rumah ${resident?.houseNo}'
                      : 'Anggota rumah · ${user.relation?.label ?? ''} · '
                          'Rumah ${resident?.houseNo}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          if (resident != null)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('No. HP'),
              subtitle: Text(resident.phone),
            ),
          if (!store.isAdmin && user.residentId != null)
            ListTile(
              leading: const Icon(Icons.family_restroom),
              title: const Text('Anggota rumah'),
              subtitle: Text(user.isPrimary
                  ? (store.joinRequestsFor(user.residentId!).isNotEmpty
                      ? '${store.joinRequestsFor(user.residentId!).length} '
                          'permintaan bergabung menunggu'
                      : 'Tambah akun keluarga atau penyewa')
                  : '${store.membersOf(user.residentId!).length + 1} orang '
                      'di rumah ini'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  push(HouseholdScreen(residentId: user.residentId!)),
            ),
          ListTile(
            leading: const Icon(Icons.construction),
            title: const Text('Ijin renovasi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const RenovationsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Pengumuman'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const AnnouncementsScreen()),
          ),
          if (store.isAdmin)
            ListTile(
              leading: const Icon(Icons.location_city_outlined),
              title: const Text('Master data'),
              subtitle: const Text(
                  'Perumahan, cluster, tipe rumah, blok, no. rumah'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(const MasterDataScreen()),
            ),
          if (store.isAdmin)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Log tamu'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(const VisitorsScreen()),
            ),
          if (store.isAdmin)
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Pendaftaran warga'),
              subtitle: Text(store.pendingRegistrations.isEmpty
                  ? 'Tidak ada yang menunggu'
                  : '${store.pendingRegistrations.length} menunggu verifikasi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(const RegistrationsScreen()),
            ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifikasi'),
            subtitle: Text([
              if (store.notifyAnnouncements) 'Pengumuman',
              if (store.notifyBills) 'Tagihan',
            ].join(' & ').ifEmpty('Semua dimatikan')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const NotificationSettingsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Ganti password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const ChangePasswordScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Tentang aplikasi'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Nilaya Living',
              applicationVersion: '0.1.0 (prototipe)',
              applicationIcon: Image.asset(
                'assets/images/app_icon.png',
                width: 48,
                height: 48,
              ),
              applicationLegalese:
                  'Nilaya (Sanskerta): kediaman, tempat bernaung.\n'
                  'Aplikasi manajemen perumahan.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Keluar',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => store.logout(),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
