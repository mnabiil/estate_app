import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../push.dart';
import '../store.dart';
import '../widgets.dart';

/// Akun → Notifikasi: pilih jenis notifikasi push yang diterima.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final permission = PushService.instance.permission;
        final denied = permission == AuthorizationStatus.denied;
        final isWarga = !store.isAdmin;

        return Scaffold(
          appBar: AppBar(title: const Text('Notifikasi')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (!store.isFirebase)
                _Info(
                  icon: Icons.info_outline,
                  color: scheme.primary,
                  text: 'Mode demo: notifikasi push tidak dikirim. Pengaturan '
                      'ini aktif setelah aplikasi terhubung ke Firebase.',
                )
              else if (denied)
                _Info(
                  icon: Icons.notifications_off_outlined,
                  color: scheme.error,
                  text: 'Izin notifikasi ditolak di HP ini. Aktifkan lewat '
                      'Pengaturan HP → Aplikasi → Nilaya Living → Notifikasi.',
                ),
              SwitchListTile(
                secondary: const Icon(Icons.campaign_outlined),
                title: const Text('Pengumuman'),
                subtitle: const Text(
                    'Pengumuman baru dari pengelola perumahan.'),
                value: store.notifyAnnouncements,
                onChanged: isWarga
                    ? (v) => runAction(
                        context, store.setNotificationPrefs(announcements: v))
                    : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.receipt_long_outlined),
                title: const Text('Tagihan IPL'),
                subtitle: const Text(
                    'Tagihan terbit, pengingat jatuh tempo (tgl 8), tagihan '
                    'terlambat (tgl 12), dan pembayaran diterima.'),
                isThreeLine: true,
                value: store.notifyBills,
                onChanged: isWarga
                    ? (v) =>
                        runAction(context, store.setNotificationPrefs(bills: v))
                    : null,
              ),
              if (!isWarga)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Notifikasi pengumuman & tagihan dikirim ke warga dan '
                    'anggota rumah. Pengumuman yang Anda buat langsung '
                    'dikirim sebagai notifikasi.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text),
      ),
    );
  }
}
