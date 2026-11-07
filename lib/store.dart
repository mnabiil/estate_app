import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'import_plan.dart';
import 'models.dart';
import 'utils.dart';

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
    _seedDemoRenovations();
    _seedDemoRegistration();
    _seedSecondDemoEstate();
  }

  AppUser? currentUser;
  final List<Resident> residents = [];
  final List<Bill> bills = [];
  final List<Complaint> complaints = [];
  final List<Visitor> visitors = [];
  final List<Announcement> announcements = [];
  final List<Renovation> renovations = [];

  /// Pengelola: pendaftaran warga mandiri di perumahan aktif.
  final List<Registration> registrations = [];

  /// Pendaftar: pendaftaran miliknya sendiri (menunggu / ditolak).
  Registration? myRegistration;

  /// Perumahan menerima pendaftaran warga mandiri.
  bool registrationOpen = true;
  final List<RenovationLog> renovationLogs = [];

  // Master perumahan.
  final List<Cluster> clusters = [];
  final List<HouseBlock> blocks = [];
  final List<House> houses = [];
  final List<HouseType> houseTypes = [];

  String estateName = 'Perumahan Griya Asri';
  String estateAddress = 'Jl. Raya Griya Asri No. 1, Bekasi';
  int fee = monthlyFee;

  /// Deposit ijin renovasi per jenis, diatur di profil perumahan.
  int depositSmall = defaultDepositSmall;
  int depositLarge = defaultDepositLarge;

  int depositFor(RenovationType t) =>
      t == RenovationType.besar ? depositLarge : depositSmall;

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

  /// Langganan nama tiap perumahan yang dikelola (untuk daftar perumahan).
  final List<StreamSubscription<dynamic>> _estateSubs = [];

  /// Langganan profil & pendaftaran milik pendaftar (menunggu verifikasi).
  final List<StreamSubscription<dynamic>> _profileSubs = [];

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
    estates.clear();
    _demoEstates.clear();
    _estateId = null;
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
    final role = Role.values.byName(d['role'] as String);
    final email = _auth!.currentUser?.email;
    if (role == Role.pendaftar) {
      _estateId = d['estateId'] as String?;
      currentUser = AppUser(
        name: d['name'] as String? ?? '',
        role: role,
        email: email,
      );
      _watchRegistration(uid);
      notifyListeners();
      return;
    }
    // Pengelola bisa mengelola beberapa perumahan (estateIds); estateId
    // adalah perumahan utama / default.
    final ids = <String>{
      if (d['estateId'] is String) d['estateId'] as String,
      if (role == Role.pengelola)
        ...((d['estateIds'] as List<dynamic>?) ?? const []).whereType<String>(),
    }.toList();
    if (ids.isEmpty) {
      throw StateError('Akun ini belum terhubung ke perumahan mana pun.');
    }
    _estateId = ids.first;
    currentUser = AppUser(
      name: d['name'] as String? ?? '',
      role: role,
      residentId: d['residentId'] as String?,
      email: email,
      mustChangePassword: d['mustChangePassword'] == true,
    );
    estates
      ..clear()
      ..addAll(ids.map((id) => EstateInfo(id: id, name: 'Perumahan')));
    for (final id in ids) {
      _watchEstateName(id);
    }
    _listen();
    notifyListeners();
  }

  /// Pendaftar: pantau pendaftaran & profil. Saat disetujui (peran berubah
  /// menjadi warga), profil dimuat ulang dan aplikasi terbuka penuh.
  void _watchRegistration(String uid) {
    _cancelProfileSubs();
    if (_estateId != null) {
      _profileSubs.add(_db!
          .collection('estates')
          .doc(_estateId)
          .collection('registrations')
          .doc(uid)
          .snapshots()
          .listen((snap) {
        final d = snap.data();
        myRegistration = d == null ? null : Registration.fromMap(snap.id, d);
        notifyListeners();
      }, onError: _onStreamError));
    }
    _profileSubs.add(
        _db!.collection('users').doc(uid).snapshots().listen((snap) async {
      final role = snap.data()?['role'];
      if (role != null && role != Role.pendaftar.name) {
        _cancelProfileSubs();
        myRegistration = null;
        try {
          await _loadProfile(uid);
        } catch (e) {
          debugPrint('Gagal memuat profil setelah disetujui: $e');
        }
      }
    }, onError: _onStreamError));
  }

  void _cancelProfileSubs() {
    for (final s in _profileSubs) {
      s.cancel();
    }
    _profileSubs.clear();
  }

  void _watchEstateName(String id) {
    _estateSubs.add(_db!.collection('estates').doc(id).snapshots().listen((s) {
      final name = s.data()?['name'] as String?;
      if (name == null) return;
      for (final e in estates) {
        if (e.id == id) e.name = name;
      }
      notifyListeners();
    }, onError: _onStreamError));
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
      registrationOpen = d['registrationOpen'] as bool? ?? true;
      fee = (d['monthlyFee'] as num?)?.toInt() ?? monthlyFee;
      depositSmall = (d['renovationDepositSmall'] as num?)?.toInt() ??
          defaultDepositSmall;
      depositLarge = (d['renovationDepositLarge'] as num?)?.toInt() ??
          defaultDepositLarge;
      notifyListeners();
    }, onError: _onStreamError));

    if (isAdmin) {
      _bind(_est.collection('registrations'), registrations,
          Registration.fromMap);
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
    _bind(_est.collection('houseTypes'), houseTypes, HouseType.fromMap);
    _bind(scoped('bills'), bills, Bill.fromMap);
    _bind(scoped('renovations'), renovations, Renovation.fromMap);
    _bind(scoped('renovationLogs'), renovationLogs, RenovationLog.fromMap);
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
    houseTypes.clear();
    renovations.clear();
    renovationLogs.clear();
    registrations.clear();
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
    _lastPassword = password;
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
    myRegistration = null;
    _demoRegistrantId = null;
    _lastPassword = null;
    if (isFirebase) {
      _cancelSubs();
      _cancelProfileSubs();
      for (final s in _estateSubs) {
        s.cancel();
      }
      _estateSubs.clear();
      estates.clear();
      _clearData();
      _estateId = null;
      await _auth!.signOut();
    } else if (estates.isNotEmpty && _estateId != estates.first.id) {
      // Demo: kembali ke perumahan contoh pertama (berisi data warga).
      await switchEstate(estates.first.id);
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

  // ---------- Ijin renovasi ----------

  Renovation? renovationById(String id) {
    for (final r in renovations) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Log barang sebuah renovasi, terbaru di atas.
  List<RenovationLog> logsOf(String renovationId) =>
      renovationLogs.where((l) => l.renovationId == renovationId).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  Renovation _renovation(String id) {
    final r = renovationById(id);
    if (r == null) throw StateError('Ijin renovasi tidak ditemukan.');
    return r;
  }

  void _requireAdmin() {
    if (!isAdmin) throw StateError('Hanya pengelola yang bisa melakukan ini.');
  }

  DocumentReference<Map<String, dynamic>> _renDoc(String id) =>
      _est.collection('renovations').doc(id);

  /// Mengunggah file ke Storage dan mengembalikan URL unduhannya.
  Future<String> _uploadFile(String path, XFile file,
      {String? contentType}) async {
    final ref = _storage!.ref(path);
    await ref.putData(
      await file.readAsBytes(),
      SettableMetadata(contentType: contentType ?? _mimeOf(file.name)),
    );
    return ref.getDownloadURL();
  }

  static String _mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.doc')) return 'application/msword';
    if (n.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (n.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  /// Folder Storage sebuah ijin renovasi (lihat storage.rules).
  String _renPath(String residentId, String renovationId) =>
      'estates/$_estateId/renovations/$residentId/$renovationId';

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Warga mengajukan ijin renovasi: detail pekerjaan, jangka waktu, dan
  /// lampiran (opsional). Deposit dibayar setelah ijin disetujui.
  Future<void> submitRenovation({
    required RenovationType type,
    required String description,
    required String contractor,
    String contractorPhone = '',
    required DateTime start,
    required DateTime end,
    List<XFile> attachments = const [],
  }) async {
    final rid = currentUser?.residentId;
    if (rid == null) throw StateError('Hanya warga yang bisa mengajukan.');
    final s = dateOnly(start), e = dateOnly(end);
    if (e.isBefore(s)) {
      throw StateError('Tanggal selesai harus setelah tanggal mulai.');
    }
    if (s.isBefore(dateOnly(DateTime.now()))) {
      throw StateError('Tanggal mulai tidak boleh di masa lalu.');
    }
    if (renovations.any((r) => r.residentId == rid && r.isActive)) {
      throw StateError('Masih ada ijin renovasi yang aktif untuk rumah ini.');
    }
    if (attachments.length > maxRenovationAttachments) {
      throw StateError('Maksimal $maxRenovationAttachments lampiran.');
    }
    final sizes = <int>[];
    for (final f in attachments) {
      final size = await f.length();
      if (size > maxAttachmentBytes) {
        throw StateError('${f.name} lebih dari ${formatFileSize(maxAttachmentBytes)}.');
      }
      sizes.add(size);
    }
    final deposit = depositFor(type);
    if (!isFirebase) {
      renovations.add(Renovation(
        id: _newId('RV'),
        residentId: rid,
        type: type,
        description: description,
        contractor: contractor,
        contractorPhone: contractorPhone,
        startDate: s,
        endDate: e,
        deposit: deposit,
        createdAt: DateTime.now(),
        attachments: [
          for (var i = 0; i < attachments.length; i++)
            RenovationAttachment(
                name: attachments[i].name,
                url: attachments[i].path,
                size: sizes[i]),
        ],
      ));
      notifyListeners();
      return;
    }
    // ID dibuat dulu agar lampiran tersimpan di folder ijin ini.
    final doc = _est.collection('renovations').doc();
    final uploaded = <Map<String, dynamic>>[];
    for (var i = 0; i < attachments.length; i++) {
      final f = attachments[i];
      final url = await _uploadFile(
          '${_renPath(rid, doc.id)}/lampiran/$i-${_safeName(f.name)}', f);
      uploaded.add(
          RenovationAttachment(name: f.name, url: url, size: sizes[i]).toMap());
    }
    await doc.set({
      'residentId': rid,
      'type': type.name,
      'description': description,
      'contractor': contractor,
      'contractorPhone': contractorPhone,
      'startDate': dayKey(s),
      'endDate': dayKey(e),
      'deposit': deposit,
      'attachments': uploaded,
      'status': RenovationStatus.diajukan.name,
      'depositStatus': DepositStatus.belumBayar.name,
      'adminNote': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Membatalkan ijin yang belum berjalan: masih diajukan, atau sudah
  /// disetujui tapi deposit belum dibayar. Warga pemilik atau pengelola.
  Future<void> cancelRenovation(String id) async {
    final r = _renovation(id);
    final cancellable = r.status == RenovationStatus.diajukan ||
        (r.status == RenovationStatus.disetujui &&
            r.depositStatus == DepositStatus.belumBayar);
    if (!cancellable) {
      throw StateError(
          'Ijin tidak bisa dibatalkan pada tahap ini. Hubungi pengelola.');
    }
    await _updateRenovation(r, {'status': RenovationStatus.dibatalkan.name},
        () => r.status = RenovationStatus.dibatalkan);
  }

  /// Pengelola menyetujui pengajuan. Setelah itu warga membayar deposit.
  Future<void> approveRenovation(String id, {String note = ''}) async {
    _requireAdmin();
    final r = _renovation(id);
    if (r.status != RenovationStatus.diajukan) {
      throw StateError('Ijin ini sudah diproses.');
    }
    await _updateRenovation(r, {
      'status': RenovationStatus.disetujui.name,
      'adminNote': note,
    }, () {
      r
        ..status = RenovationStatus.disetujui
        ..adminNote = note;
    });
  }

  Future<void> rejectRenovation(String id, String reason) async {
    _requireAdmin();
    final r = _renovation(id);
    if (r.status != RenovationStatus.diajukan) {
      throw StateError('Ijin ini sudah diproses.');
    }
    await _updateRenovation(r, {
      'status': RenovationStatus.ditolak.name,
      'adminNote': reason,
    }, () {
      r
        ..status = RenovationStatus.ditolak
        ..adminNote = reason;
    });
  }

  /// Warga membayar deposit setelah ijin disetujui, dengan bukti transfer
  /// (opsional untuk tunai). Pengelola lalu memverifikasi.
  Future<void> payDeposit(String id,
      {required String method, XFile? proof}) async {
    final r = _renovation(id);
    if (currentUser?.residentId != r.residentId) {
      throw StateError('Ini bukan ijin renovasi rumah Anda.');
    }
    if (r.status != RenovationStatus.disetujui ||
        r.depositStatus != DepositStatus.belumBayar) {
      throw StateError('Deposit dibayar setelah ijin disetujui.');
    }
    final now = DateTime.now();
    if (!isFirebase) {
      r
        ..depositStatus = DepositStatus.menungguVerifikasi
        ..depositMethod = method
        ..depositProofUrl = proof?.path
        ..depositSubmittedAt = now;
      notifyListeners();
      return;
    }
    final proofUrl = proof == null
        ? null
        : await _uploadFile(
            '${_renPath(r.residentId, r.id)}/deposit/bukti-${now.millisecondsSinceEpoch}.jpg',
            proof,
            contentType: 'image/jpeg');
    await _renDoc(r.id).update({
      'depositStatus': DepositStatus.menungguVerifikasi.name,
      'depositMethod': method,
      'depositProofUrl': proofUrl,
      'depositSubmittedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Pengelola mengonfirmasi deposit diterima (verifikasi bukti transfer,
  /// atau pembayaran tunai langsung). Setelah ini pekerjaan boleh dimulai.
  Future<void> markDepositPaid(String id) async {
    _requireAdmin();
    final r = _renovation(id);
    if (r.status != RenovationStatus.disetujui ||
        r.depositStatus == DepositStatus.dibayar ||
        r.depositStatus == DepositStatus.dikembalikan) {
      throw StateError('Deposit dicatat setelah ijin disetujui.');
    }
    final now = DateTime.now();
    final method = r.depositMethod ?? 'Tunai ke pengelola';
    await _updateRenovation(r, {
      'depositStatus': DepositStatus.dibayar.name,
      'depositMethod': method,
      'depositPaidAt': FieldValue.serverTimestamp(),
    }, () {
      r
        ..depositStatus = DepositStatus.dibayar
        ..depositMethod = method
        ..depositPaidAt = now;
    });
  }

  /// Bukti pembayaran tidak valid: warga diminta membayar / mengunggah ulang.
  Future<void> rejectDepositProof(String id, String reason) async {
    _requireAdmin();
    final r = _renovation(id);
    if (r.depositStatus != DepositStatus.menungguVerifikasi) {
      throw StateError('Tidak ada pembayaran yang menunggu verifikasi.');
    }
    await _updateRenovation(r, {
      'depositStatus': DepositStatus.belumBayar.name,
      'depositProofUrl': null,
      'adminNote': reason,
    }, () {
      r
        ..depositStatus = DepositStatus.belumBayar
        ..depositProofUrl = null
        ..adminNote = reason;
    });
  }

  /// Memperpanjang jangka waktu pekerjaan.
  Future<void> extendRenovation(String id, DateTime newEnd) async {
    _requireAdmin();
    final r = _renovation(id);
    if (r.status != RenovationStatus.disetujui) {
      throw StateError('Hanya renovasi yang disetujui yang bisa diperpanjang.');
    }
    final e = dateOnly(newEnd);
    if (!e.isAfter(r.endDate)) {
      throw StateError('Tanggal baru harus setelah ${formatDate(r.endDate)}.');
    }
    await _updateRenovation(
        r, {'endDate': dayKey(e)}, () => r.endDate = e);
  }

  Future<void> completeRenovation(String id, {String note = ''}) async {
    _requireAdmin();
    final r = _renovation(id);
    if (!r.canWork) {
      throw StateError(
          'Hanya renovasi yang berjalan (deposit diterima) yang bisa diselesaikan.');
    }
    final newNote = note.isEmpty ? r.adminNote : note;
    await _updateRenovation(r, {
      'status': RenovationStatus.selesai.name,
      'adminNote': newNote,
    }, () {
      r
        ..status = RenovationStatus.selesai
        ..adminNote = newNote;
    });
  }

  /// Mengembalikan deposit (penuh atau dipotong) setelah renovasi selesai.
  Future<void> refundDeposit(String id, int amount, {String note = ''}) async {
    _requireAdmin();
    final r = _renovation(id);
    if (r.depositStatus != DepositStatus.dibayar) {
      throw StateError('Deposit belum diterima atau sudah dikembalikan.');
    }
    if (r.isActive) {
      throw StateError('Selesaikan renovasi dulu.');
    }
    if (amount < 0 || amount > r.deposit) {
      throw StateError('Jumlah pengembalian harus 0 – ${formatRupiah(r.deposit)}.');
    }
    final newNote = note.isEmpty ? r.adminNote : note;
    final now = DateTime.now();
    await _updateRenovation(r, {
      'depositStatus': DepositStatus.dikembalikan.name,
      'depositRefund': amount,
      'depositRefundedAt': FieldValue.serverTimestamp(),
      'adminNote': newNote,
    }, () {
      r
        ..depositStatus = DepositStatus.dikembalikan
        ..depositRefund = amount
        ..depositRefundedAt = now
        ..adminNote = newNote;
    });
  }

  Future<void> _updateRenovation(
      Renovation r, Map<String, Object?> data, void Function() local) async {
    if (!isFirebase) {
      local();
      notifyListeners();
      return;
    }
    await _renDoc(r.id).update(data);
  }

  /// Mencatat barang masuk/keluar beserta foto (opsional). Hanya saat
  /// pekerjaan berjalan: ijin disetujui dan deposit diterima.
  Future<void> addRenovationLog(
    String renovationId, {
    required LogDirection direction,
    required String item,
    required String quantity,
    String note = '',
    List<XFile> photos = const [],
  }) async {
    final r = _renovation(renovationId);
    if (!r.canWork) {
      throw StateError('Barang dicatat setelah ijin disetujui dan deposit '
          'diterima pengelola.');
    }
    if (!isAdmin && currentUser?.residentId != r.residentId) {
      throw StateError('Ini bukan renovasi rumah Anda.');
    }
    if (photos.length > maxLogPhotos) {
      throw StateError('Maksimal $maxLogPhotos foto.');
    }
    final by = currentUser?.name ?? '';
    if (!isFirebase) {
      renovationLogs.add(RenovationLog(
        id: _newId('LG'),
        renovationId: r.id,
        residentId: r.residentId,
        direction: direction,
        item: item,
        quantity: quantity,
        note: note,
        at: DateTime.now(),
        recordedBy: by,
        photos: photos.map((p) => p.path).toList(),
      ));
      notifyListeners();
      return;
    }
    final doc = _est.collection('renovationLogs').doc();
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      urls.add(await _uploadFile(
          '${_renPath(r.residentId, r.id)}/barang/${doc.id}/$i.jpg', photos[i],
          contentType: 'image/jpeg'));
    }
    await doc.set({
      'renovationId': r.id,
      'residentId': r.residentId,
      'direction': direction.name,
      'item': item,
      'quantity': quantity,
      'note': note,
      'photoUrls': urls,
      'at': FieldValue.serverTimestamp(),
      'recordedBy': by,
    });
  }

  // ---------- Password ----------

  /// Mengganti password. [current] boleh null hanya saat wajib ganti setelah
  /// login pertama (password sementara diingat sejak login).
  Future<void> changePassword({String? current, required String newPassword}) async {
    final user = currentUser;
    if (user == null) throw StateError('Silakan login terlebih dahulu.');
    final problem = passwordProblem(newPassword);
    if (problem != null) throw StateError('Password baru: $problem.');
    final old = current ?? _lastPassword;
    if (old != null && old == newPassword) {
      throw StateError('Password baru harus berbeda dari password lama.');
    }
    if (!isFirebase) {
      if (current != null && current.isEmpty) {
        throw StateError('Isi password lama.');
      }
      currentUser = user.copyWith(mustChangePassword: false);
      notifyListeners();
      return;
    }
    final authUser = _auth!.currentUser!;
    if (old == null) throw StateError('Isi password lama.');
    try {
      await authUser.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: authUser.email!, password: old));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw StateError('Password lama salah.');
      }
      rethrow;
    }
    await authUser.updatePassword(newPassword);
    _lastPassword = newPassword;
    if (user.mustChangePassword) {
      await _db!
          .collection('users')
          .doc(authUser.uid)
          .update({'mustChangePassword': false});
    }
    currentUser = user.copyWith(mustChangePassword: false);
    notifyListeners();
  }

  /// Password terakhir yang dipakai login (hanya di memori, untuk
  /// konfirmasi ulang saat wajib ganti password).
  String? _lastPassword;

  // ---------- Registrasi mandiri warga ----------

  /// Perumahan yang menerima pendaftaran warga mandiri.
  Future<List<RegistrationEstate>> registrationEstates() async {
    if (!isFirebase) {
      return [
        for (final e in estates)
          if (_demoEstateOpen(e.id))
            RegistrationEstate(
              id: e.id,
              name: e.id == _estateId ? estateName : e.name,
              address: e.id == _estateId
                  ? estateAddress
                  : (_demoEstates[e.id]?.address ?? ''),
            ),
      ];
    }
    final res = await _fn!
        .httpsCallable('listRegistrationEstates')
        .call<Map<String, dynamic>>();
    return [
      for (final e in (res.data['estates'] as List<dynamic>? ?? const []))
        RegistrationEstate(
          id: (e as Map)['id'] as String,
          name: e['name'] as String? ?? '',
          address: e['address'] as String? ?? '',
        ),
    ];
  }

  bool _demoEstateOpen(String id) => id == _estateId
      ? registrationOpen
      : (_demoEstates[id]?.registrationOpen ?? true);

  /// Master data + rumah yang tersedia untuk didaftarkan.
  Future<RegistrationOptions> registrationOptions(String estateId) async {
    if (!isFirebase) {
      final active = estateId == _estateId;
      final d = active ? null : _demoEstates[estateId];
      final hs = active ? houses : d?.houses ?? const <House>[];
      final rs = active ? residents : d?.residents ?? const <Resident>[];
      final regs = active ? registrations : d?.registrations ?? const <Registration>[];
      final occupied = {
        for (final r in rs)
          if (r.houseId != null) r.houseId!,
        for (final g in regs)
          if (g.status == RegistrationStatus.menunggu &&
              g.id != _demoRegistrantId)
            g.houseId,
      };
      return RegistrationOptions(
        clusters: List.of(active ? clusters : d?.clusters ?? const []),
        types: List.of(active ? houseTypes : d?.houseTypes ?? const []),
        blocks: List.of(active ? blocks : d?.blocks ?? const []),
        houses: List.of(hs),
        available: {
          for (final h in hs)
            if (!occupied.contains(h.id)) h.id,
        },
      );
    }
    final res = await _fn!
        .httpsCallable('getRegistrationOptions')
        .call<Map<String, dynamic>>({'estateId': estateId});
    return RegistrationOptions.fromMap(res.data);
  }

  /// Mode demo: ID pendaftaran milik "pendaftar" yang sedang login.
  String? _demoRegistrantId;

  /// Pendaftaran warga mandiri. Membuat akun (email & password) bila belum
  /// ada, lalu mengirim data untuk diverifikasi pengelola. Juga dipakai
  /// untuk mengajukan ulang setelah ditolak (tanpa email/password).
  Future<void> registerResident({
    required String estateId,
    required String houseId,
    required String name,
    required String phone,
    required Occupancy occupancy,
    String? email,
    String? password,
    XFile? document,
  }) async {
    final resubmit = currentUser?.role == Role.pendaftar;
    if (!resubmit) {
      if (email == null || !email.contains('@')) {
        throw StateError('Email tidak valid.');
      }
      final problem = passwordProblem(password ?? '');
      if (problem != null) throw StateError('Password: $problem.');
    }
    if (name.trim().isEmpty || phone.trim().isEmpty) {
      throw StateError('Nama dan No. HP wajib diisi.');
    }

    if (!isFirebase) {
      _demoRegister(
        estateId: estateId,
        houseId: houseId,
        name: name,
        phone: phone,
        occupancy: occupancy,
        email: resubmit ? currentUser!.email! : email!.toLowerCase(),
        document: document,
        resubmit: resubmit,
      );
      return;
    }

    // 1. Akun login (atau pakai akun yang sudah ada bila pendaftaran
    //    sebelumnya terputus / ditolak).
    if (!resubmit) {
      try {
        await _auth!.createUserWithEmailAndPassword(
            email: email!.trim(), password: password!);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        try {
          await _auth!.signInWithEmailAndPassword(
              email: email!.trim(), password: password!);
        } on FirebaseAuthException {
          throw StateError('Email sudah terdaftar. Silakan login, atau '
              'gunakan "Lupa password".');
        }
      }
      _lastPassword = password;
    }
    final uid = _auth!.currentUser!.uid;

    // 2. Dokumen pendukung (opsional).
    String? docUrl;
    if (document != null) {
      final ref = _storage!.ref(
          'estates/$estateId/registrations/$uid/dokumen-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(await document.readAsBytes(),
          SettableMetadata(contentType: 'image/jpeg'));
      docUrl = await ref.getDownloadURL();
    }

    // 3. Kirim pendaftaran (divalidasi server).
    await _fn!.httpsCallable('submitRegistration').call<void>({
      'estateId': estateId,
      'houseId': houseId,
      'name': name.trim(),
      'phone': phone.trim(),
      'occupancy': occupancy.name,
      'docUrl': docUrl,
    });
    await _loadProfile(uid);
  }

  void _demoRegister({
    required String estateId,
    required String houseId,
    required String name,
    required String phone,
    required Occupancy occupancy,
    required String email,
    required bool resubmit,
    XFile? document,
  }) {
    final active = estateId == _estateId;
    final d = active ? null : _demoEstates[estateId];
    final regs = active ? registrations : d!.registrations;
    final hs = active ? houses : d!.houses;
    final bs = active ? blocks : d!.blocks;
    final cs = active ? clusters : d!.clusters;
    final rs = active ? residents : d!.residents;
    if (!resubmit &&
        (rs.any((r) => (r.email ?? '').toLowerCase() == email) ||
            regs.any((g) =>
                g.email == email && g.status != RegistrationStatus.ditolak))) {
      throw StateError('Email sudah terdaftar.');
    }
    final h = hs.where((h) => h.id == houseId).firstOrNull;
    if (h == null) throw StateError('Rumah tidak ditemukan.');
    final taken = rs.any((r) => r.houseId == houseId) ||
        regs.any((g) =>
            g.houseId == houseId &&
            g.status == RegistrationStatus.menunggu &&
            g.id != _demoRegistrantId);
    if (taken) throw StateError('Rumah ini sudah berpenghuni atau sedang diajukan.');
    final label =
        '${bs.where((b) => b.id == h.blockId).firstOrNull?.name ?? '?'}/${h.number}';
    final clusterName =
        cs.where((c) => c.id == h.clusterId).firstOrNull?.name ?? '';
    var reg = resubmit
        ? regs.where((g) => g.id == _demoRegistrantId).firstOrNull
        : null;
    if (reg == null) {
      reg = Registration(
        id: _newId('REG'),
        estateId: estateId,
        name: name,
        phone: phone,
        email: email,
        houseId: houseId,
        houseNo: label,
        clusterName: clusterName,
        occupancy: occupancy,
        docUrl: document?.path,
        createdAt: DateTime.now(),
      );
      regs.add(reg);
    } else {
      reg
        ..name = name
        ..phone = phone
        ..houseId = houseId
        ..houseNo = label
        ..clusterName = clusterName
        ..occupancy = occupancy
        ..docUrl = document?.path ?? reg.docUrl
        ..status = RegistrationStatus.menunggu
        ..note = ''
        ..createdAt = DateTime.now()
        ..reviewedAt = null;
    }
    _demoRegistrantId = reg.id;
    myRegistration = reg;
    currentUser = AppUser(name: name, role: Role.pendaftar, email: email);
    notifyListeners();
  }

  Registration? registrationById(String id) =>
      registrations.where((r) => r.id == id).firstOrNull;

  List<Registration> get pendingRegistrations => registrations
      .where((r) => r.status == RegistrationStatus.menunggu)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Pengelola menyetujui: akun pendaftar menjadi warga di rumah pilihannya.
  Future<void> approveRegistration(String id) async {
    _requireAdmin();
    final reg = registrationById(id);
    if (reg == null || reg.status != RegistrationStatus.menunggu) {
      throw StateError('Pendaftaran tidak ditemukan atau sudah diproses.');
    }
    if (!isFirebase) {
      final h = houseById(reg.houseId);
      if (h == null) throw StateError('Rumah sudah tidak ada di master data.');
      final occupant = residentOfHouse(h.id);
      if (occupant != null) {
        throw StateError('Rumah ${houseLabel(h)} sudah ditempati ${occupant.name}.');
      }
      residents.add(Resident(
        id: _newId('R'),
        name: reg.name,
        houseNo: houseLabel(h),
        houseId: h.id,
        phone: reg.phone,
        email: reg.email,
      ));
      reg
        ..status = RegistrationStatus.disetujui
        ..reviewedAt = DateTime.now();
      notifyListeners();
      return;
    }
    await _fn!.httpsCallable('approveRegistration').call<void>({
      'estateId': _estateId,
      'uid': id,
    });
  }

  Future<void> rejectRegistration(String id, String reason) async {
    _requireAdmin();
    final reg = registrationById(id);
    if (reg == null || reg.status != RegistrationStatus.menunggu) {
      throw StateError('Pendaftaran tidak ditemukan atau sudah diproses.');
    }
    if (reason.trim().isEmpty) throw StateError('Isi alasan penolakan.');
    if (!isFirebase) {
      reg
        ..status = RegistrationStatus.ditolak
        ..note = reason
        ..reviewedAt = DateTime.now();
      notifyListeners();
      return;
    }
    await _est.collection('registrations').doc(id).update({
      'status': RegistrationStatus.ditolak.name,
      'note': reason,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Import dari Excel ----------

  /// Menjalankan rencana import (lihat lib/excel_io.dart) ke perumahan aktif.
  /// Data yang sudah ada dipakai ulang berdasarkan nama. [onProgress]
  /// menerima keterangan langkah yang sedang berjalan.
  Future<ImportResult> applyImport(ImportPlan plan,
      {void Function(String step)? onProgress}) async {
    _requireAdmin();
    if (plan.hasErrors) {
      throw StateError('Perbaiki error di file terlebih dahulu.');
    }
    final result = ImportResult();

    // Peta nama -> ID (data yang ada + yang akan dibuat).
    final clusterIds = {for (final c in clusters) normName(c.name): c.id};
    final typeIds = {
      for (final t in houseTypes) '${t.clusterId}|${normName(t.name)}': t.id,
    };
    final blockIds = {
      for (final b in blocks) '${b.clusterId}|${normName(b.name)}': b.id,
    };
    String newId(String col, String demoPrefix) => isFirebase
        ? _est.collection(col).doc().id
        : _newId(demoPrefix);

    final newClusters = <Cluster>[];
    for (final name in plan.clusters) {
      final c = Cluster(id: newId('clusters', 'C'), name: name);
      clusterIds[normName(name)] = c.id;
      newClusters.add(c);
    }
    final newTypes = <HouseType>[];
    for (final t in plan.types) {
      final cid = clusterIds[normName(t.cluster)]!;
      final type = HouseType(
        id: newId('houseTypes', 'T'),
        clusterId: cid,
        name: t.name,
        buildingArea: t.buildingArea,
        landArea: t.landArea,
      );
      typeIds['$cid|${normName(t.name)}'] = type.id;
      newTypes.add(type);
    }
    final newBlocks = <HouseBlock>[];
    for (final b in plan.blocks) {
      final cid = clusterIds[normName(b.cluster)]!;
      final block = HouseBlock(
        id: newId('blocks', 'K'),
        clusterId: cid,
        name: b.name,
        typeId: typeIds['$cid|${normName(b.type)}'],
      );
      blockIds['$cid|${normName(b.name)}'] = block.id;
      newBlocks.add(block);
    }
    final newHouses = <House>[];
    for (final h in plan.houses) {
      final cid = clusterIds[normName(h.cluster)]!;
      newHouses.add(House(
        id: newId('houses', 'H'),
        clusterId: cid,
        blockId: blockIds['$cid|${normName(h.block)}']!,
        number: h.number,
      ));
    }

    if (!isFirebase) {
      clusters.addAll(newClusters);
      houseTypes.addAll(newTypes);
      blocks.addAll(newBlocks);
      houses.addAll(newHouses);
    } else {
      // Bertahap: aturan keamanan blok memeriksa cluster & tipe yang sudah
      // tersimpan, dan satu batch dibatasi jumlah pemeriksaan dokumennya.
      onProgress?.call('Menyimpan cluster & tipe rumah…');
      await _commitChunks([
        for (final c in newClusters)
          (WriteBatch b) =>
              b.set(_est.collection('clusters').doc(c.id), {'name': c.name}),
        for (final t in newTypes)
          (WriteBatch b) => b.set(_est.collection('houseTypes').doc(t.id), {
                'clusterId': t.clusterId,
                'name': t.name,
                'buildingArea': t.buildingArea,
                'landArea': t.landArea,
              }),
      ], 400);
      onProgress?.call('Menyimpan blok…');
      await _commitChunks([
        for (final k in newBlocks)
          (WriteBatch b) => b.set(_est.collection('blocks').doc(k.id), {
                'clusterId': k.clusterId,
                'typeId': k.typeId,
                'name': k.name,
              }),
      ], 5);
      onProgress?.call('Menyimpan ${newHouses.length} nomor rumah…');
      await _commitChunks([
        for (final h in newHouses)
          (WriteBatch b) => b.set(_est.collection('houses').doc(h.id), {
                'clusterId': h.clusterId,
                'blockId': h.blockId,
                'number': h.number,
              }),
      ], 400);
    }
    result
      ..clusters = newClusters.length
      ..types = newTypes.length
      ..blocks = newBlocks.length
      ..houses = newHouses.length;

    // Warga: rumah dicari dari data yang ada + yang baru dibuat.
    final allHouses = [...houses, if (isFirebase) ...newHouses];
    final blockNameById = {
      for (final b in [...blocks, if (isFirebase) ...newBlocks]) b.id: b.name,
    };
    House? findHouse(PlanResident r) {
      final cid = clusterIds[normName(r.cluster)];
      final bid = blockIds['$cid|${normName(r.block)}'];
      for (final h in allHouses) {
        if (h.blockId == bid && normNumber(h.number) == normNumber(r.number)) {
          return h;
        }
      }
      return null;
    }

    for (var i = 0; i < plan.residents.length; i++) {
      final r = plan.residents[i];
      final h = findHouse(r);
      final label = h == null ? '${r.block}/${r.number}' : '${blockNameById[h.blockId]}/${h.number}';
      if (h == null) {
        result.accounts.add(ResidentAccount(
            name: r.name, house: label, email: r.email,
            error: 'Rumah tidak ditemukan'));
        continue;
      }
      if (!isFirebase) {
        residents.add(Resident(
          id: _newId('R'),
          name: r.name,
          houseNo: label,
          houseId: h.id,
          phone: r.phone,
          email: r.email.isEmpty ? null : r.email,
        ));
        result.residents++;
        result.accounts.add(
            ResidentAccount(name: r.name, house: label, email: r.email));
        continue;
      }
      onProgress?.call('Membuat akun warga ${i + 1}/${plan.residents.length}…');
      try {
        final res = await _fn!
            .httpsCallable('createResident')
            .call<Map<String, dynamic>>({
          'estateId': _estateId,
          'name': r.name,
          'houseId': h.id,
          'phone': r.phone,
          'email': r.email,
        });
        result.residents++;
        result.accounts.add(ResidentAccount(
          name: r.name,
          house: label,
          email: r.email,
          password: res.data['tempPassword'] as String?,
        ));
      } catch (e) {
        result.accounts.add(ResidentAccount(
            name: r.name, house: label, email: r.email, error: describeError(e)));
      }
    }
    if (!isFirebase) notifyListeners();
    return result;
  }

  Future<void> _commitChunks(
      List<void Function(WriteBatch)> writes, int size) async {
    for (var i = 0; i < writes.length; i += size) {
      final batch = _db!.batch();
      for (final w in writes.skip(i).take(size)) {
        w(batch);
      }
      await batch.commit();
    }
  }

  // ---------- Atur rumah warga (termasuk warga lama) ----------

  /// Warga yang belum terhubung ke master rumah: data lama yang nomor
  /// rumahnya diketik manual, atau rumahnya sudah dihapus dari master.
  List<Resident> get unlinkedResidents => residents
      .where((r) => r.houseId == null || houseById(r.houseId!) == null)
      .toList();

  static String _normLabel(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\s.\-_]'), '')
      // "a1/5" sama dengan "a1/05".
      .replaceAll(RegExp(r'(?<=/)0+(?=\d)'), '');

  /// Rumah di master yang labelnya sama dengan teks [label] (mis. "A1/05"),
  /// tanpa membedakan huruf besar/kecil & spasi. Null bila tidak ada atau
  /// labelnya ambigu (blok bernama sama di beberapa cluster).
  House? houseMatchingLabel(String label) {
    final want = _normLabel(label);
    if (want.isEmpty) return null;
    final found = houses.where((h) => _normLabel(houseLabel(h)) == want);
    return found.length == 1 ? found.first : null;
  }

  /// Menghubungkan / memindahkan warga ke rumah [houseId].
  Future<void> assignHouse(String residentId, String houseId) async {
    final r = residentById(residentId);
    if (r == null) throw StateError('Warga tidak ditemukan.');
    final h = houseById(houseId);
    if (h == null) throw StateError('Rumah tidak ditemukan.');
    final occupant = residentOfHouse(houseId);
    if (occupant != null && occupant.id != residentId) {
      throw StateError(
          'Rumah ${houseLabel(h)} sudah ditempati ${occupant.name}.');
    }
    final label = houseLabel(h);
    if (!isFirebase) {
      r
        ..houseId = houseId
        ..houseNo = label;
      notifyListeners();
      return;
    }
    await _est
        .collection('residents')
        .doc(residentId)
        .update({'houseId': houseId, 'houseNo': label});
  }

  /// Menghubungkan otomatis warga lama yang teks nomor rumahnya cocok dengan
  /// rumah kosong di master. Mengembalikan (terhubung, masih belum terhubung).
  Future<(int, int)> autoLinkResidents() async {
    final pending = unlinkedResidents;
    final taken = <String>{};
    final pairs = <(Resident, House)>[];
    for (final r in pending) {
      final h = houseMatchingLabel(r.houseNo);
      if (h == null || taken.contains(h.id)) continue;
      if (residentOfHouse(h.id) != null) continue;
      taken.add(h.id);
      pairs.add((r, h));
    }
    if (pairs.isEmpty) return (0, pending.length);
    if (!isFirebase) {
      for (final (r, h) in pairs) {
        r
          ..houseId = h.id
          ..houseNo = houseLabel(h);
      }
      notifyListeners();
    } else {
      for (var i = 0; i < pairs.length; i += 400) {
        final batch = _db!.batch();
        for (final (r, h) in pairs.skip(i).take(400)) {
          batch.update(_est.collection('residents').doc(r.id),
              {'houseId': h.id, 'houseNo': houseLabel(h)});
        }
        await batch.commit();
      }
    }
    return (pairs.length, pending.length - pairs.length);
  }

  // ---------- Perumahan (bisa lebih dari satu untuk pengelola) ----------

  /// Perumahan yang bisa diakses akun ini. Warga: satu. Pengelola: bisa banyak.
  final List<EstateInfo> estates = [];

  /// ID perumahan yang sedang aktif (semua layar menampilkan data perumahan ini).
  String? get activeEstateId => _estateId;

  /// Mode demo: data perumahan yang sedang tidak aktif disimpan di sini.
  final Map<String, _DemoEstate> _demoEstates = {};

  /// Pindah ke perumahan lain yang dikelola akun ini.
  Future<void> switchEstate(String id) async {
    if (id == _estateId) return;
    if (!estates.any((e) => e.id == id)) {
      throw StateError('Perumahan tidak ditemukan.');
    }
    if (!isFirebase) {
      _demoEstates[_estateId!] = _DemoEstate.capture(this);
      _clearData();
      _estateId = id;
      (_demoEstates.remove(id) ?? _DemoEstate.empty(estateNameOf(id)))
          .restore(this);
      notifyListeners();
      return;
    }
    _estateId = id;
    _clearData();
    estateName = estateNameOf(id);
    _listen();
    notifyListeners();
  }

  String estateNameOf(String id) {
    for (final e in estates) {
      if (e.id == id) return e.name;
    }
    return 'Perumahan';
  }

  /// Pengelola membuat perumahan baru lalu langsung pindah ke sana.
  Future<void> createEstate({
    required String name,
    required String address,
    required int fee,
    int depositSmall = defaultDepositSmall,
    int depositLarge = defaultDepositLarge,
  }) async {
    _checkName(name, estates.map((e) => e.name), 'Perumahan');
    String id;
    if (!isFirebase) {
      id = _newId('E');
      estates.add(EstateInfo(id: id, name: name));
      _demoEstates[id] = _DemoEstate.empty(name, address: address, fee: fee)
        ..depositSmall = depositSmall
        ..depositLarge = depositLarge;
    } else {
      final res =
          await _fn!.httpsCallable('createEstate').call<Map<String, dynamic>>({
        'name': name,
        'address': address,
        'monthlyFee': fee,
        'renovationDepositSmall': depositSmall,
        'renovationDepositLarge': depositLarge,
      });
      id = res.data['estateId'] as String;
      estates.add(EstateInfo(id: id, name: name));
      _watchEstateName(id);
    }
    await switchEstate(id);
  }

  // ---------- Master: Cluster > Tipe rumah > Blok > No. rumah ----------

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

  HouseType? houseTypeById(String? id) {
    if (id == null) return null;
    for (final t in houseTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Tipe sebuah rumah = tipe bloknya.
  HouseType? houseTypeOf(House h) =>
      houseTypeById(blockById(h.blockId)?.typeId);

  List<Cluster> get sortedClusters =>
      clusters.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Tipe rumah di sebuah cluster, urut luas bangunan lalu nama.
  List<HouseType> typesOf(String clusterId) =>
      houseTypes.where((t) => t.clusterId == clusterId).toList()
        ..sort((a, b) {
          final byArea = (a.buildingArea ?? 1 << 30)
              .compareTo(b.buildingArea ?? 1 << 30);
          return byArea != 0 ? byArea : a.name.compareTo(b.name);
        });

  /// Blok di sebuah cluster. Bila [typeId] diisi, hanya blok bertipe itu;
  /// gunakan [noTypeId] untuk blok lama yang belum bertipe.
  List<HouseBlock> blocksOf(String clusterId, {String? typeId}) => blocks
      .where((b) =>
          b.clusterId == clusterId &&
          (typeId == null ||
              (typeId == noTypeId ? b.typeId == null : b.typeId == typeId)))
      .toList()
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

  Future<void> updateEstate({
    required String name,
    required String address,
    required int fee,
    int? depositSmall,
    int? depositLarge,
    bool? registrationOpen,
  }) async {
    final open = registrationOpen ?? this.registrationOpen;
    final small = depositSmall ?? this.depositSmall;
    final large = depositLarge ?? this.depositLarge;
    if (small <= 0 || large <= 0) {
      throw StateError('Deposit renovasi harus lebih dari 0.');
    }
    _checkName(
        name,
        estates.where((e) => e.id != _estateId).map((e) => e.name),
        'Perumahan');
    if (!isFirebase) {
      estateName = name;
      estateAddress = address;
      this.fee = fee;
      this.depositSmall = small;
      this.depositLarge = large;
      this.registrationOpen = open;
      for (final e in estates) {
        if (e.id == _estateId) e.name = name;
      }
      notifyListeners();
      return;
    }
    await _est.update({
      'name': name,
      'address': address,
      'monthlyFee': fee,
      'renovationDepositSmall': small,
      'renovationDepositLarge': large,
      'registrationOpen': open,
    });
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
    if (houseTypes.any((t) => t.clusterId == id)) {
      throw StateError('Hapus dulu semua tipe rumah di cluster ini.');
    }
    if (!isFirebase) {
      clusters.removeWhere((c) => c.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('clusters').doc(id).delete();
  }

  Future<void> saveHouseType(String clusterId, String name,
      {String? id, int? buildingArea, int? landArea}) async {
    _checkName(
        name,
        houseTypes
            .where((t) => t.clusterId == clusterId && t.id != id)
            .map((t) => t.name),
        'Tipe');
    if (!isFirebase) {
      if (id == null) {
        houseTypes.add(HouseType(
            id: _newId('T'),
            clusterId: clusterId,
            name: name,
            buildingArea: buildingArea,
            landArea: landArea));
      } else {
        houseTypeById(id)!
          ..name = name
          ..buildingArea = buildingArea
          ..landArea = landArea;
      }
      notifyListeners();
      return;
    }
    final col = _est.collection('houseTypes');
    await (id == null ? col.doc() : col.doc(id)).set({
      'clusterId': clusterId,
      'name': name,
      'buildingArea': buildingArea,
      'landArea': landArea,
    });
  }

  Future<void> deleteHouseType(String id) async {
    final used = blocks.where((b) => b.typeId == id).length;
    if (used > 0) {
      throw StateError('Tipe ini masih dipakai $used blok.');
    }
    if (!isFirebase) {
      houseTypes.removeWhere((t) => t.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('houseTypes').doc(id).delete();
  }

  /// Menyimpan blok. Setiap blok wajib punya satu tipe dari cluster yang sama.
  Future<void> saveBlock(String clusterId, String name,
      {String? id, required String typeId}) async {
    final type = houseTypeById(typeId);
    if (type == null || type.clusterId != clusterId) {
      throw StateError('Pilih tipe rumah dari cluster ini.');
    }
    _checkName(
        name,
        blocks
            .where((b) => b.clusterId == clusterId && b.id != id)
            .map((b) => b.name),
        'Blok');
    if (!isFirebase) {
      if (id == null) {
        blocks.add(HouseBlock(
            id: _newId('K'), clusterId: clusterId, name: name, typeId: typeId));
      } else {
        blockById(id)!
          ..name = name
          ..typeId = typeId;
      }
      notifyListeners();
      return;
    }
    final col = _est.collection('blocks');
    await (id == null ? col.doc() : col.doc(id))
        .set({'clusterId': clusterId, 'typeId': typeId, 'name': name});
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

  /// Contoh ijin renovasi: satu berjalan (dengan log barang), satu menunggu
  /// persetujuan (dengan lampiran), satu disetujui menunggu deposit.
  void _seedDemoRenovations() {
    final today = dateOnly(DateTime.now());
    final running = Renovation(
      id: _newId('RV'),
      residentId: 'R1',
      type: RenovationType.kecil,
      description: 'Ganti keramik dapur dan cat ulang ruang tamu.',
      contractor: 'Pak Slamet',
      contractorPhone: '0812-7777-1212',
      startDate: today.subtract(const Duration(days: 5)),
      endDate: today.add(const Duration(days: 9)),
      deposit: depositSmall,
      createdAt: today.subtract(const Duration(days: 8)),
      status: RenovationStatus.disetujui,
      depositStatus: DepositStatus.dibayar,
      depositMethod: 'Transfer bank',
      depositPaidAt: today.subtract(const Duration(days: 7)),
    );
    renovations.add(running);
    const logs = [
      (5, LogDirection.masuk, 'Keramik 40x40', '12 dus', 'Pick up B 1234 XY'),
      (5, LogDirection.masuk, 'Semen instan', '10 sak', ''),
      (3, LogDirection.keluar, 'Puing bongkaran keramik', '6 karung', 'Dibuang ke TPS'),
      (1, LogDirection.masuk, 'Cat tembok 20 L', '2 pail', ''),
    ];
    for (final (daysAgo, dir, item, qty, note) in logs) {
      renovationLogs.add(RenovationLog(
        id: _newId('LG'),
        renovationId: running.id,
        residentId: 'R1',
        direction: dir,
        item: item,
        quantity: qty,
        note: note,
        at: today
            .subtract(Duration(days: daysAgo))
            .add(const Duration(hours: 9, minutes: 30)),
        recordedBy: 'Pak Hendra',
      ));
    }
    renovations.add(Renovation(
      id: _newId('RV'),
      residentId: 'R4',
      type: RenovationType.besar,
      description: 'Tambah kamar di lantai 2 dan ubah fasad depan.',
      contractor: 'CV Bangun Jaya',
      contractorPhone: '021-555-8899',
      startDate: today.add(const Duration(days: 7)),
      endDate: today.add(const Duration(days: 96)),
      deposit: depositLarge,
      createdAt: today.subtract(const Duration(days: 1)),
      attachments: const [
        RenovationAttachment(name: 'denah-lantai-2.pdf', url: '', size: 845000),
        RenovationAttachment(name: 'tampak-depan.jpg', url: '', size: 1240000),
      ],
    ));
    renovations.add(Renovation(
      id: _newId('RV'),
      residentId: 'R6',
      type: RenovationType.kecil,
      description: 'Pasang kanopi carport dan cat pagar.',
      contractor: 'Pak Darto',
      startDate: today.add(const Duration(days: 3)),
      endDate: today.add(const Duration(days: 12)),
      deposit: depositSmall,
      createdAt: today.subtract(const Duration(days: 2)),
      status: RenovationStatus.disetujui,
      adminNote: 'Jam kerja 08.00–17.00, Minggu libur.',
    ));
  }

  /// Contoh pendaftaran warga mandiri yang menunggu verifikasi.
  void _seedDemoRegistration() {
    final b1 = blocks.firstWhere((b) => b.name == 'B1');
    final h = housesOf(b1.id).firstWhere((h) => h.number == '11');
    registrations.add(Registration(
      id: 'REG-DEMO',
      estateId: _estateId!,
      name: 'Hendra Gunawan',
      phone: '0813-9090-1122',
      email: 'hendra.g@contoh.id',
      houseId: h.id,
      houseNo: houseLabel(h),
      clusterName: clusterById(h.clusterId)?.name ?? '',
      occupancy: Occupancy.penyewa,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ));
  }

  /// Perumahan contoh kedua milik pengelola yang sama: master data saja.
  void _seedSecondDemoEstate() {
    final d = _DemoEstate(
      name: 'Nilaya Residence',
      address: 'Jl. Nilaya Raya No. 8, Tangerang',
      fee: 300000,
    );
    final c = Cluster(id: _newId('C'), name: 'Cluster Melati');
    final t = HouseType(
        id: _newId('T'),
        clusterId: c.id,
        name: 'Tipe 60/120',
        buildingArea: 60,
        landArea: 120);
    final b = HouseBlock(id: _newId('K'), clusterId: c.id, name: 'M1', typeId: t.id);
    d.clusters.add(c);
    d.houseTypes.add(t);
    d.blocks.add(b);
    for (var n = 1; n <= 8; n++) {
      d.houses.add(House(
        id: _newId('H'),
        clusterId: c.id,
        blockId: b.id,
        number: n.toString().padLeft(2, '0'),
      ));
    }
    _demoEstates['nilaya-residence'] = d;
  }

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
    // Warga lama: nomor rumah diketik manual, belum terhubung ke master.
    // "A2/06" cocok dengan master (bisa dihubungkan otomatis); "Blok C 3"
    // tidak cocok sehingga perlu diatur manual.
    const legacy = [
      ('Lina Hartati', 'A2/06', '0819-2468-1357'),
      ('Bayu Saputra', 'Blok C 3', '0896-1357-2468'),
    ];
    // Dua perumahan contoh. Perumahan pertama berisi data lengkap.
    _estateId = 'griya-asri';
    estates.addAll([
      EstateInfo(id: 'griya-asri', name: estateName),
      EstateInfo(id: 'nilaya-residence', name: 'Nilaya Residence'),
    ]);

    // Master: Cluster > Tipe > Blok > No. rumah (01-12 per blok).
    const master = {
      'Cluster Anggrek': [
        ('Tipe 36/72', 36, 72, ['A1']),
        ('Tipe 45/90', 45, 90, ['A2']),
      ],
      'Cluster Bougenville': [
        ('Tipe 45/90', 45, 90, ['B1']),
        ('Tipe 54/108', 54, 108, ['B2']),
      ],
    };
    for (final MapEntry(key: clusterName, value: types) in master.entries) {
      final c = Cluster(id: _newId('C'), name: clusterName);
      clusters.add(c);
      for (final (typeName, lb, lt, blockNames) in types) {
        final t = HouseType(
            id: _newId('T'),
            clusterId: c.id,
            name: typeName,
            buildingArea: lb,
            landArea: lt);
        houseTypes.add(t);
        for (final bn in blockNames) {
          final b = HouseBlock(
              id: _newId('K'), clusterId: c.id, name: bn, typeId: t.id);
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
    for (var i = 0; i < legacy.length; i++) {
      final (name, house, phone) = legacy[i];
      residents.add(Resident(
        id: 'R${data.length + i + 1}',
        name: name,
        houseNo: house,
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

/// Data satu perumahan di mode demo, disimpan saat perumahan lain aktif.
class _DemoEstate {
  _DemoEstate({
    required this.name,
    this.address = '',
    this.fee = monthlyFee,
  });

  factory _DemoEstate.empty(String name, {String address = '', int? fee}) =>
      _DemoEstate(name: name, address: address, fee: fee ?? monthlyFee);

  factory _DemoEstate.capture(EstateStore s) => _DemoEstate(
        name: s.estateName,
        address: s.estateAddress,
        fee: s.fee,
      )
        ..residents.addAll(s.residents)
        ..bills.addAll(s.bills)
        ..complaints.addAll(s.complaints)
        ..visitors.addAll(s.visitors)
        ..announcements.addAll(s.announcements)
        ..clusters.addAll(s.clusters)
        ..blocks.addAll(s.blocks)
        ..houses.addAll(s.houses)
        ..houseTypes.addAll(s.houseTypes)
        ..renovations.addAll(s.renovations)
        ..renovationLogs.addAll(s.renovationLogs)
        ..depositSmall = s.depositSmall
        ..depositLarge = s.depositLarge
        ..registrationOpen = s.registrationOpen
        ..registrations.addAll(s.registrations);

  final String name;
  final String address;
  final int fee;
  int depositSmall = defaultDepositSmall;
  int depositLarge = defaultDepositLarge;
  bool registrationOpen = true;
  final registrations = <Registration>[];
  final renovations = <Renovation>[];
  final renovationLogs = <RenovationLog>[];
  final residents = <Resident>[];
  final bills = <Bill>[];
  final complaints = <Complaint>[];
  final visitors = <Visitor>[];
  final announcements = <Announcement>[];
  final clusters = <Cluster>[];
  final blocks = <HouseBlock>[];
  final houses = <House>[];
  final houseTypes = <HouseType>[];

  void restore(EstateStore s) {
    s.estateName = name;
    s.estateAddress = address;
    s.fee = fee;
    s.residents.addAll(residents);
    s.bills.addAll(bills);
    s.complaints.addAll(complaints);
    s.visitors.addAll(visitors);
    s.announcements.addAll(announcements);
    s.clusters.addAll(clusters);
    s.blocks.addAll(blocks);
    s.houses.addAll(houses);
    s.houseTypes.addAll(houseTypes);
    s.renovations.addAll(renovations);
    s.renovationLogs.addAll(renovationLogs);
    s.depositSmall = depositSmall;
    s.depositLarge = depositLarge;
    s.registrationOpen = registrationOpen;
    s.registrations.addAll(registrations);
  }
}
