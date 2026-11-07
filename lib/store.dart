import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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

  // Master perumahan.
  final List<Cluster> clusters = [];
  final List<HouseBlock> blocks = [];
  final List<House> houses = [];

  String estateName = 'Perumahan Griya Asri';
  String estateAddress = 'Jl. Raya Griya Asri No. 1, Bekasi';
  int fee = monthlyFee;

  final _random = Random();
  int _seq = 1000;
  String _newId(String prefix) => '$prefix${_seq++}';

  // ---------- Firebase ----------

  FirebaseFirestore? _db;
  FirebaseAuth? _auth;
  FirebaseFunctions? _fn;
  FirebaseStorage? _storage;
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
    _storage = FirebaseStorage.instance;
    _clearData();
    estateName = 'Perumahan';

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
      estateAddress = d['address'] as String? ?? '';
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
    _bind(_est.collection('clusters'), clusters, Cluster.fromMap);
    _bind(_est.collection('blocks'), blocks, HouseBlock.fromMap);
    _bind(_est.collection('houses'), houses, House.fromMap);
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
    clusters.clear();
    blocks.clear();
    houses.clear();
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

  /// Menambah warga di rumah [houseId] (dari master rumah). Di mode Firebase
  /// sekaligus membuat akun login lewat Cloud Function dan mengembalikan
  /// password sementaranya.
  Future<String?> addResident(String name, String houseId, String phone,
      {String? email}) async {
    final house = houseById(houseId);
    if (house == null) throw StateError('Rumah tidak ditemukan.');
    if (residentOfHouse(houseId) != null) {
      throw StateError('Rumah ${houseLabel(house)} sudah berpenghuni.');
    }
    if (!isFirebase) {
      residents.add(Resident(
        id: _newId('R'),
        name: name,
        houseNo: houseLabel(house),
        houseId: houseId,
        phone: phone,
      ));
      notifyListeners();
      return null;
    }
    final res =
        await _fn!.httpsCallable('createResident').call<Map<String, dynamic>>({
      'estateId': _estateId,
      'name': name,
      'houseId': houseId,
      'phone': phone,
      'email': email,
    });
    return res.data['tempPassword'] as String?;
  }

  // ---------- Master perumahan ----------

  Cluster? clusterById(String id) {
    for (final c in clusters) {
      if (c.id == id) return c;
    }
    return null;
  }

  HouseBlock? blockById(String id) {
    for (final b in blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  House? houseById(String id) {
    for (final h in houses) {
      if (h.id == id) return h;
    }
    return null;
  }

  List<Cluster> get sortedClusters =>
      clusters.toList()..sort((a, b) => a.name.compareTo(b.name));

  List<HouseBlock> blocksOf(String clusterId) =>
      blocks.where((b) => b.clusterId == clusterId).toList()
        ..sort((a, b) => compareHouseNumber(a.name, b.name));

  List<House> housesOf(String blockId) =>
      houses.where((h) => h.blockId == blockId).toList()
        ..sort((a, b) => compareHouseNumber(a.number, b.number));

  /// Label rumah, mis. "A1/05".
  String houseLabel(House h) => '${blockById(h.blockId)?.name ?? '?'}/${h.number}';

  /// Warga yang menempati rumah ini, atau null bila kosong.
  Resident? residentOfHouse(String houseId) {
    for (final r in residents) {
      if (r.houseId == houseId) return r;
    }
    return null;
  }

  Future<void> updateEstate(
      {required String name, required String address, required int fee}) async {
    if (!isFirebase) {
      estateName = name;
      estateAddress = address;
      this.fee = fee;
      notifyListeners();
      return;
    }
    await _est.update({'name': name, 'address': address, 'monthlyFee': fee});
  }

  void _checkName(String name, Iterable<String> existing, String what) {
    final n = name.trim().toLowerCase();
    if (existing.any((e) => e.trim().toLowerCase() == n)) {
      throw StateError('$what "$name" sudah ada.');
    }
  }

  Future<void> saveCluster(String name, {String? id}) async {
    _checkName(name, clusters.where((c) => c.id != id).map((c) => c.name),
        'Cluster');
    if (!isFirebase) {
      if (id == null) {
        clusters.add(Cluster(id: _newId('C'), name: name));
      } else {
        clusterById(id)!.name = name;
      }
      notifyListeners();
      return;
    }
    final col = _est.collection('clusters');
    await (id == null ? col.doc() : col.doc(id)).set({'name': name});
  }

  Future<void> deleteCluster(String id) async {
    if (blocks.any((b) => b.clusterId == id)) {
      throw StateError('Hapus dulu semua blok di cluster ini.');
    }
    if (!isFirebase) {
      clusters.removeWhere((c) => c.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('clusters').doc(id).delete();
  }

  Future<void> saveBlock(String clusterId, String name, {String? id}) async {
    _checkName(
        name,
        blocks
            .where((b) => b.clusterId == clusterId && b.id != id)
            .map((b) => b.name),
        'Blok');
    if (!isFirebase) {
      if (id == null) {
        blocks.add(HouseBlock(id: _newId('K'), clusterId: clusterId, name: name));
      } else {
        blockById(id)!.name = name;
      }
      notifyListeners();
      return;
    }
    final col = _est.collection('blocks');
    await (id == null ? col.doc() : col.doc(id))
        .set({'clusterId': clusterId, 'name': name});
  }

  Future<void> deleteBlock(String id) async {
    if (houses.any((h) => h.blockId == id)) {
      throw StateError('Hapus dulu semua nomor rumah di blok ini.');
    }
    if (!isFirebase) {
      blocks.removeWhere((b) => b.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('blocks').doc(id).delete();
  }

  /// Menambah nomor rumah ke blok. Nomor yang sudah ada dilewati.
  /// Mengembalikan jumlah nomor yang benar-benar ditambahkan.
  Future<int> addHouses(String blockId, List<String> numbers) async {
    final block = blockById(blockId)!;
    final existing = housesOf(blockId).map((h) => h.number.toLowerCase()).toSet();
    final fresh = <String>[];
    for (final n in numbers.map((n) => n.trim())) {
      if (n.isNotEmpty && existing.add(n.toLowerCase())) fresh.add(n);
    }
    if (fresh.isEmpty) return 0;
    if (fresh.length > 300) {
      throw StateError('Maksimal 300 nomor sekaligus.');
    }
    if (!isFirebase) {
      for (final n in fresh) {
        houses.add(House(
            id: _newId('H'),
            clusterId: block.clusterId,
            blockId: blockId,
            number: n));
      }
      notifyListeners();
      return fresh.length;
    }
    final batch = _db!.batch();
    for (final n in fresh) {
      batch.set(_est.collection('houses').doc(), {
        'clusterId': block.clusterId,
        'blockId': blockId,
        'number': n,
      });
    }
    await batch.commit();
    return fresh.length;
  }

  Future<void> deleteHouse(String id) async {
    final r = residentOfHouse(id);
    if (r != null) {
      throw StateError('Rumah ini masih ditempati ${r.name}.');
    }
    if (!isFirebase) {
      houses.removeWhere((h) => h.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('houses').doc(id).delete();
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
    String title,
    String description,
    String category, {
    List<XFile> photos = const [],
  }) async {
    final rid = currentUser!.residentId!;
    if (photos.length > maxComplaintPhotos) {
      throw ArgumentError('Maksimal $maxComplaintPhotos foto');
    }
    if (!isFirebase) {
      complaints.add(Complaint(
        id: _newId('K'),
        residentId: rid,
        title: title,
        description: description,
        category: category,
        createdAt: DateTime.now(),
        photos: photos.map((p) => p.path).toList(),
      ));
      notifyListeners();
      return;
    }
    // ID dokumen dibuat dulu supaya foto bisa disimpan di folder keluhan ini.
    final doc = _est.collection('complaints').doc();
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      urls.add(await _uploadComplaintPhoto(rid, doc.id, i, photos[i]));
    }
    await doc.set({
      'residentId': rid,
      'title': title,
      'description': description,
      'category': category,
      'status': ComplaintStatus.baru.name,
      'photoUrls': urls,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Path: estates/{estateId}/complaints/{residentId}/{complaintId}/{n}.jpg
  /// (lihat storage.rules).
  Future<String> _uploadComplaintPhoto(
      String residentId, String complaintId, int index, XFile file) async {
    final ref = _storage!.ref(
        'estates/$_estateId/complaints/$residentId/$complaintId/$index.jpg');
    await ref.putData(
      await file.readAsBytes(),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
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
    // Master: 2 cluster, masing-masing 2 blok, tiap blok rumah no. 01-12.
    const master = {
      'Cluster Anggrek': ['A1', 'A2'],
      'Cluster Bougenville': ['B1', 'B2'],
    };
    for (final MapEntry(key: clusterName, value: blockNames)
        in master.entries) {
      final c = Cluster(id: _newId('C'), name: clusterName);
      clusters.add(c);
      for (final bn in blockNames) {
        final b = HouseBlock(id: _newId('K'), clusterId: c.id, name: bn);
        blocks.add(b);
        for (var n = 1; n <= 12; n++) {
          houses.add(House(
            id: _newId('H'),
            clusterId: c.id,
            blockId: b.id,
            number: n.toString().padLeft(2, '0'),
          ));
        }
      }
    }
    String? houseIdFor(String label) {
      for (final h in houses) {
        if (houseLabel(h) == label) return h.id;
      }
      return null;
    }

    for (var i = 0; i < data.length; i++) {
      final (name, house, phone) = data[i];
      residents.add(Resident(
        id: 'R${i + 1}',
        name: name,
        houseNo: house,
        houseId: houseIdFor(house),
        phone: phone,
      ));
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
