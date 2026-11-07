import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

/// Satu-satunya sumber data aplikasi.
///
/// - **Mode demo** (default): data contoh di memori, login tanpa password.
/// - **Mode Firebase**: aktif bila `Firebase.initializeApp` berhasil
///   (setelah `flutterfire configure`). Data dibaca realtime dari Firestore.
final store = EstateStore();

/// Region Cloud Functions & Firestore (Jakarta).
const firebaseRegion = 'asia-southeast2';

/// Tarif IPL default bila dokumen perumahan tidak menyebutkan `monthlyFee`.
const monthlyFee = 250000;

/// Nama perumahan yang sedang aktif (dipakai di banyak layar).
String get estateName => store.estateName;

class EstateStore extends ChangeNotifier {
  EstateStore() {
    _seedDemo();
  }

  AppUser? currentUser;
  final List<Resident> residents = [];
  final List<Bill> bills = [];
  final List<Complaint> complaints = [];
  final List<Visitor> visitors = [];
  final List<Announcement> announcements = [];

  String estateName = 'Perumahan Griya Asri';
  int fee = monthlyFee;

  final _random = Random();
  int _seq = 1000;
  String _newId(String prefix) => '$prefix${_seq++}';

  // ---------- Firebase ----------

  FirebaseFirestore? _db;
  FirebaseAuth? _auth;
  FirebaseFunctions? _fn;
  String? _estateId;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool get isFirebase => _db != null;

  DocumentReference<Map<String, dynamic>> get _est =>
      _db!.collection('estates').doc(_estateId);

  /// Dipanggil sekali di `main()` setelah Firebase berhasil diinisialisasi.
  Future<void> enableFirebase() async {
    _db = FirebaseFirestore.instance;
    _auth = FirebaseAuth.instance;
    _fn = FirebaseFunctions.instanceFor(region: firebaseRegion);
    _clearData();
    estateName = 'Griya Kita';

    // Pulihkan sesi login sebelumnya.
    final user = _auth!.currentUser;
    if (user != null) {
      try {
        await _loadProfile(user.uid);
      } catch (e) {
        debugPrint('Gagal memulihkan sesi: $e');
        await _auth!.signOut();
      }
    }
  }

  Future<void> _loadProfile(String uid) async {
    final snap = await _db!.collection('users').doc(uid).get();
    final d = snap.data();
    if (d == null) {
      throw StateError(
          'Akun ini belum terdaftar di perumahan mana pun. Hubungi pengelola.');
    }
    _estateId = d['estateId'] as String;
    currentUser = AppUser(
      name: d['name'] as String? ?? '',
      role: Role.values.byName(d['role'] as String),
      residentId: d['residentId'] as String?,
    );
    _listen();
    notifyListeners();
  }

  void _listen() {
    _cancelSubs();
    final rid = currentUser!.residentId;

    // Warga hanya boleh membaca dokumen miliknya (lihat firestore.rules),
    // jadi query-nya harus difilter residentId.
    Query<Map<String, dynamic>> scoped(String col) => isAdmin
        ? _est.collection(col)
        : _est.collection(col).where('residentId', isEqualTo: rid);

    _subs.add(_est.snapshots().listen((s) {
      final d = s.data() ?? const {};
      estateName = d['name'] as String? ?? 'Perumahan';
      fee = (d['monthlyFee'] as num?)?.toInt() ?? monthlyFee;
      notifyListeners();
    }, onError: _onStreamError));

    if (isAdmin) {
      _bind(_est.collection('residents'), residents, Resident.fromMap);
    } else {
      _subs.add(_est.collection('residents').doc(rid).snapshots().listen((s) {
        residents
          ..clear()
          ..addAll([if (s.data() != null) Resident.fromMap(s.id, s.data()!)]);
        notifyListeners();
      }, onError: _onStreamError));
    }
    _bind(scoped('bills'), bills, Bill.fromMap);
    _bind(scoped('complaints'), complaints, Complaint.fromMap);
    _bind(scoped('visitors'), visitors, Visitor.fromMap);
    _bind(
      _est
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(50),
      announcements,
      Announcement.fromMap,
    );
  }

  void _bind<T>(
    Query<Map<String, dynamic>> query,
    List<T> target,
    T Function(String id, Map<String, dynamic> data) parse,
  ) {
    _subs.add(query.snapshots().listen((snap) {
      target
        ..clear()
        ..addAll(snap.docs.map((d) => parse(d.id, d.data())));
      notifyListeners();
    }, onError: _onStreamError));
  }

  void _onStreamError(Object e) => debugPrint('Firestore stream error: $e');

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _clearData() {
    residents.clear();
    bills.clear();
    complaints.clear();
    visitors.clear();
    announcements.clear();
  }

  // ---------- Sesi ----------

  bool get isAdmin => currentUser?.role == Role.pengelola;

  Resident? get currentResident {
    final id = currentUser?.residentId;
    return id == null ? null : residentById(id);
  }

  /// Login mode demo.
  void login(Role role, {String? residentId}) {
    if (role == Role.pengelola) {
      currentUser = const AppUser(name: 'Pak Hendra', role: Role.pengelola);
    } else {
      final r = residentById(residentId!)!;
      currentUser = AppUser(name: r.name, role: Role.warga, residentId: r.id);
    }
    notifyListeners();
  }

  /// Login mode Firebase.
  Future<void> signInWithEmail(String email, String password) async {
    final cred = await _auth!
        .signInWithEmailAndPassword(email: email, password: password);
    try {
      await _loadProfile(cred.user!.uid);
    } catch (_) {
      await _auth!.signOut();
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) =>
      _auth!.sendPasswordResetEmail(email: email);

  Future<void> logout() async {
    currentUser = null;
    if (isFirebase) {
      _cancelSubs();
      _clearData();
      _estateId = null;
      await _auth!.signOut();
    }
    notifyListeners();
  }

  // ---------- Warga ----------

  Resident? residentById(String id) {
    for (final r in residents) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Menambah warga. Di mode Firebase sekaligus membuat akun login lewat
  /// Cloud Function dan mengembalikan password sementaranya.
  Future<String?> addResident(String name, String houseNo, String phone,
      {String? email}) async {
    if (!isFirebase) {
      residents.add(Resident(
          id: _newId('R'), name: name, houseNo: houseNo, phone: phone));
      notifyListeners();
      return null;
    }
    final res =
        await _fn!.httpsCallable('createResident').call<Map<String, dynamic>>({
      'estateId': _estateId,
      'name': name,
      'houseNo': houseNo,
      'phone': phone,
      'email': email,
    });
    return res.data['tempPassword'] as String?;
  }

  // ---------- Tagihan IPL ----------

  List<Bill> billsForResident(String residentId) =>
      bills.where((b) => b.residentId == residentId).toList();

  int unpaidTotal(String residentId) => billsForResident(residentId)
      .where((b) => b.status == BillStatus.belumBayar)
      .fold(0, (total, b) => total + b.amount);

  /// Warga: bayar lewat server (Cloud Function). Pengelola: tandai lunas (tunai).
  Future<void> payBill(String billId, String method) async {
    if (!isFirebase) {
      bills.firstWhere((b) => b.id == billId)
        ..status = BillStatus.lunas
        ..paidAt = DateTime.now()
        ..method = method;
      notifyListeners();
      return;
    }
    if (isAdmin) {
      await _est.collection('bills').doc(billId).update({
        'status': BillStatus.lunas.name,
        'paidAt': FieldValue.serverTimestamp(),
        'method': method,
      });
    } else {
      await _fn!.httpsCallable('payBill').call<void>({
        'estateId': _estateId,
        'billId': billId,
        'method': method,
      });
    }
  }

  /// Membuat tagihan bulan berjalan untuk warga yang belum punya.
  /// Mengembalikan jumlah tagihan baru.
  Future<int> generateBillsForCurrentMonth() async {
    final now = DateTime.now();
    final period = DateTime(now.year, now.month);
    final missing = residents
        .where((r) =>
            !bills.any((b) => b.residentId == r.id && b.period == period))
        .toList();
    if (missing.isEmpty) return 0;

    if (!isFirebase) {
      for (final r in missing) {
        bills.add(Bill(
            id: _newId('B'), residentId: r.id, period: period, amount: fee));
      }
      notifyListeners();
      return missing.length;
    }
    final batch = _db!.batch();
    for (final r in missing) {
      final bill = Bill(id: '', residentId: r.id, period: period, amount: fee);
      batch.set(_est.collection('bills').doc(Bill.docId(r.id, period)), {
        ...bill.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return missing.length;
  }

  // ---------- Keluhan ----------

  Future<void> addComplaint(
      String title, String description, String category) async {
    final rid = currentUser!.residentId!;
    if (!isFirebase) {
      complaints.add(Complaint(
        id: _newId('K'),
        residentId: rid,
        title: title,
        description: description,
        category: category,
        createdAt: DateTime.now(),
      ));
      notifyListeners();
      return;
    }
    await _est.collection('complaints').add({
      'residentId': rid,
      'title': title,
      'description': description,
      'category': category,
      'status': ComplaintStatus.baru.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateComplaintStatus(String id, ComplaintStatus status) async {
    if (!isFirebase) {
      complaints.firstWhere((c) => c.id == id).status = status;
      notifyListeners();
      return;
    }
    await _est.collection('complaints').doc(id).update({'status': status.name});
  }

  // ---------- Tamu ----------

  Future<Visitor> addVisitor(
      String name, String purpose, DateTime visitDate) async {
    final ref = isFirebase ? _est.collection('visitors').doc() : null;
    final visitor = Visitor(
      id: ref?.id ?? _newId('T'),
      residentId: currentUser!.residentId!,
      name: name,
      purpose: purpose,
      visitDate: visitDate,
      code: (100000 + _random.nextInt(900000)).toString(),
    );
    if (ref == null) {
      visitors.add(visitor);
      notifyListeners();
    } else {
      await ref.set(visitor.toMap());
    }
    return visitor;
  }

  Future<void> checkInVisitor(String id) async {
    if (!isFirebase) {
      visitors.firstWhere((v) => v.id == id).checkedInAt = DateTime.now();
      notifyListeners();
      return;
    }
    await _est.collection('visitors').doc(id).update({
      'checkedInAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Pengumuman ----------

  Future<void> addAnnouncement(String title, String body) async {
    if (!isFirebase) {
      announcements.insert(
        0,
        Announcement(
            id: _newId('P'),
            title: title,
            body: body,
            createdAt: DateTime.now()),
      );
      notifyListeners();
      return;
    }
    await _est.collection('announcements').add({
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Data contoh (mode demo) ----------

  void _seedDemo() {
    const data = [
      ('Budi Santoso', 'A1/05', '0812-3456-7890'),
      ('Siti Rahmawati', 'A1/07', '0813-2233-4455'),
      ('Andi Pratama', 'A2/01', '0815-9988-7766'),
      ('Dewi Lestari', 'A2/12', '0817-1122-3344'),
      ('Rudi Hartono', 'B1/03', '0821-5566-7788'),
      ('Maya Kusuma', 'B1/09', '0822-4433-2211'),
      ('Joko Susilo', 'B2/04', '0838-6655-4433'),
      ('Rina Marlina', 'B2/10', '0857-7788-9900'),
    ];
    for (var i = 0; i < data.length; i++) {
      final (name, house, phone) = data[i];
      residents.add(
          Resident(id: 'R${i + 1}', name: name, houseNo: house, phone: phone));
    }

    final now = DateTime.now();
    for (var m = 2; m >= 0; m--) {
      final period = DateTime(now.year, now.month - m);
      for (var i = 0; i < residents.length; i++) {
        final r = residents[i];
        // Bulan lalu: hampir semua lunas. Bulan ini: sebagian saja.
        final paid = m > 0 ? r.id != 'R3' : i % 3 == 2;
        bills.add(Bill(
          id: _newId('B'),
          residentId: r.id,
          period: period,
          amount: monthlyFee,
          status: paid ? BillStatus.lunas : BillStatus.belumBayar,
          paidAt: paid ? DateTime(period.year, period.month, 5) : null,
          method: paid ? 'Transfer Bank' : null,
        ));
      }
    }

    complaints.addAll([
      Complaint(
        id: _newId('K'),
        residentId: 'R1',
        title: 'Lampu jalan blok A1 mati',
        description:
            'Lampu jalan depan rumah A1/05 sampai A1/09 mati sejak 3 hari lalu.',
        category: 'Fasilitas',
        createdAt: now.subtract(const Duration(days: 3)),
        status: ComplaintStatus.diproses,
      ),
      Complaint(
        id: _newId('K'),
        residentId: 'R4',
        title: 'Sampah belum diangkut',
        description: 'Sampah di blok A2 belum diangkut sejak Senin.',
        category: 'Kebersihan',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Complaint(
        id: _newId('K'),
        residentId: 'R1',
        title: 'Portal belakang rusak',
        description: 'Palang portal belakang tidak bisa turun.',
        category: 'Keamanan',
        createdAt: now.subtract(const Duration(days: 12)),
        status: ComplaintStatus.selesai,
      ),
    ]);

    final today = DateTime(now.year, now.month, now.day);
    visitors.addAll([
      Visitor(
        id: _newId('T'),
        residentId: 'R1',
        name: 'Ahmad (Kurir paket)',
        purpose: 'Antar paket',
        visitDate: today,
        code: '482913',
      ),
      Visitor(
        id: _newId('T'),
        residentId: 'R5',
        name: 'Keluarga Pak Darto',
        purpose: 'Silaturahmi',
        visitDate: today,
        code: '730155',
        checkedInAt: now.subtract(const Duration(hours: 1)),
      ),
    ]);

    announcements.addAll([
      Announcement(
        id: _newId('P'),
        title: 'Kerja bakti hari Minggu',
        body:
            'Kerja bakti membersihkan saluran air seluruh blok, Minggu pukul 07.00. '
            'Mohon perwakilan setiap rumah hadir.',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Announcement(
        id: _newId('P'),
        title: 'Pembayaran IPL paling lambat tanggal 10',
        body:
            'IPL bulan ini sebesar Rp 250.000 dapat dibayar melalui aplikasi. '
            'Keterlambatan akan dikenakan pengingat dari pengelola.',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      Announcement(
        id: _newId('P'),
        title: 'Pemadaman air PDAM',
        body:
            'Akan ada pemadaman air pada hari Rabu pukul 09.00-15.00 untuk perbaikan pipa.',
        createdAt: now.subtract(const Duration(days: 8)),
      ),
    ]);
  }
}

/// Mengubah error Firebase menjadi pesan yang bisa dibaca warga.
String describeError(Object e) {
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Email atau password salah.',
      'invalid-email' => 'Format email tidak valid.',
      'too-many-requests' => 'Terlalu banyak percobaan. Coba lagi nanti.',
      'network-request-failed' => 'Tidak ada koneksi internet.',
      _ => e.message ?? e.code,
    };
  }
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  if (e is FirebaseException) {
    return e.code == 'permission-denied'
        ? 'Anda tidak punya akses untuk tindakan ini.'
        : e.message ?? e.code;
  }
  if (e is StateError) return e.message;
  return e.toString();
}
