import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tujuan navigasi dari notifikasi yang diketuk.
enum PushTarget { bills, announcements }

/// Notifikasi push lewat Firebase Cloud Messaging.
///
/// Token perangkat disimpan di `users/{uid}/devices/{token}`; server
/// (Cloud Functions) mengirim notifikasi pengumuman & tagihan ke token
/// milik warga yang bersangkutan.
class PushService {
  PushService._();
  static final instance = PushService._();

  /// Untuk banner saat aplikasi terbuka (dipasang di MaterialApp).
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Notifikasi yang diketuk; HomeShell membuka halaman yang sesuai.
  final target = ValueNotifier<PushTarget?>(null);

  /// Status izin terakhir (null bila belum pernah diminta / mode demo).
  AuthorizationStatus? permission;

  final List<StreamSubscription<dynamic>> _subs = [];
  String? _uid;
  String? _token;

  /// Dipanggil setelah login (mode Firebase).
  Future<void> register(String uid) async {
    if (_uid == uid) return;
    await unregister();
    _uid = uid;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      permission = settings.authorizationStatus;
      if (permission == AuthorizationStatus.denied) return;

      await messaging.setForegroundNotificationPresentationOptions(
          alert: false, badge: true, sound: true);
      _token = await messaging.getToken();
      if (_token != null) await _saveToken(uid, _token!);
      _subs.add(messaging.onTokenRefresh.listen((t) async {
        _token = t;
        await _saveToken(uid, t);
      }));

      _subs.add(FirebaseMessaging.onMessage.listen(_showBanner));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      debugPrint('Notifikasi push tidak aktif: $e');
    }
  }

  /// Dipanggil sebelum logout: perangkat ini berhenti menerima notifikasi
  /// untuk akun tersebut.
  Future<void> unregister() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final uid = _uid, token = _token;
    _uid = null;
    _token = null;
    if (uid == null || token == null) return;
    try {
      await _devices(uid).doc(token).delete();
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Gagal menghapus token push: $e');
    }
  }

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('devices');

  Future<void> _saveToken(String uid, String token) =>
      _devices(uid).doc(token).set({
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static PushTarget? _targetOf(RemoteMessage m) => switch (m.data['type']) {
        'bill' => PushTarget.bills,
        'announcement' => PushTarget.announcements,
        _ => null,
      };

  void _open(RemoteMessage m) => target.value = _targetOf(m);

  /// Aplikasi sedang terbuka: tampilkan sebagai banner di dalam aplikasi.
  void _showBanner(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    final to = _targetOf(m);
    messengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.title ?? '',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((n.body ?? '').isNotEmpty) Text(n.body!),
        ],
      ),
      action: to == null
          ? null
          : SnackBarAction(label: 'Lihat', onPressed: () => target.value = to),
    ));
  }
}
