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
import 'push.dart';
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
    _seedDemoStaff();
    _seedDemoPayments();
    // Anggota rumah contoh: istri Budi Santoso (A1/05).
    members.add(HouseholdMember(
      id: 'M-ANI',
      residentId: 'R1',
      name: 'Ani Santoso',
      relation: MemberRelation.pasangan,
      phone: '0812-3456-7000',
      email: 'ani@contoh.id',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ));
    _seedSecondDemoEstate();
  }

  AppUser? currentUser;
  final List<Resident> residents = [];
  final List<Bill> bills = [];
  final List<Complaint> complaints = [];
  final List<Visitor> visitors = [];
  final List<Announcement> announcements = [];
  final List<Renovation> renovations = [];

  /// Pembayaran IPL. Pengelola: semua; warga: rumahnya.
  final List<Payment> payments = [];

  /// Rekening tujuan transfer perumahan aktif.
  final List<BankAccount> bankAccounts = [];

  /// Tim pengelola & level akses perumahan aktif.
  final List<StaffMember> staff = [];
  final List<AdminRole> adminRoles = [];

  /// Anggota rumah (keluarga/penyewa). Pengelola: semua; warga: rumahnya.
  final List<HouseholdMember> members = [];

  /// Pengelola: pendaftaran warga mandiri di perumahan aktif.
  final List<Registration> registrations = [];

  /// Pendaftar: pendaftaran miliknya sendiri (menunggu / ditolak).
  Registration? myRegistration;

  /// Perumahan menerima pendaftaran warga mandiri.
  bool registrationOpen = true;

  /// Preferensi notifikasi push akun ini.
  bool notifyAnnouncements = true;
  bool notifyBills = true;
  final List<RenovationLog> renovationLogs = [];

  // Master perumahan.
  final List<Cluster> clusters = [];
  final List<HouseBlock> blocks = [];
  final List<House> houses = [];
  final List<HouseType> houseTypes = [];

  String estateName = 'Perumahan Griya Asri';
  String estateAddress = 'Jl. Raya Griya Asri No. 1, Bekasi';
  int fee = monthlyFee;

  /// Tanggal jatuh tempo IPL setiap bulan (1–28).
  int billDueDay = defaultBillDueDay;

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
    // Warga: bisa punya beberapa rumah (di satu/beberapa perumahan).
    final homeList =
        role == Role.warga ? HomeRef.fromProfile(d) : const <HomeRef>[];
    if (homeList.isNotEmpty) {
      ids
        ..clear()
        ..addAll({for (final h in homeList) h.estateId});
    }
    if (ids.isEmpty) {
      throw StateError('Akun ini belum terhubung ke perumahan mana pun.');
    }
    final active = homeList.where((h) => h.key == _activeHomeKey).firstOrNull ??
        homeList.firstOrNull;
    _activeHomeKey = active?.key;
    homes
      ..clear()
      ..addAll(homeList);
    _estateId = active?.estateId ?? ids.first;
    final relation = d['relation'] as String?;
    final prefs = (d['notifPrefs'] as Map<String, dynamic>?) ?? const {};
    notifyAnnouncements = prefs['announcements'] != false;
    notifyBills = prefs['bills'] != false;
    currentUser = AppUser(
      name: d['name'] as String? ?? '',
      role: role,
      residentId: d['residentId'] as String?,
      email: email,
      mustChangePassword: d['mustChangePassword'] == true,
      isPrimary: d['householdRole'] != 'anggota',
      relation: relation == null ? null : MemberRelation.values.byName(relation),
    );
    if (active != null) currentUser = currentUser!.forHome(active);
    estates
      ..clear()
      ..addAll(ids.map((id) => EstateInfo(id: id, name: 'Perumahan')));
    for (final id in ids) {
      _watchEstateName(id);
    }
    _listen();
    notifyListeners();
    // Notifikasi push (izin & token perangkat) tanpa menahan login.
    unawaited(PushService.instance.register(uid));
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
    syncProblems.clear();
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
      bankAccounts
        ..clear()
        ..addAll(BankAccount.listFrom(d['bankAccounts']));
      fee = (d['monthlyFee'] as num?)?.toInt() ?? monthlyFee;
      billDueDay = (d['billDueDay'] as num?)?.toInt() ?? defaultBillDueDay;
      depositSmall = (d['renovationDepositSmall'] as num?)?.toInt() ??
          defaultDepositSmall;
      depositLarge = (d['renovationDepositLarge'] as num?)?.toInt() ??
          defaultDepositLarge;
      notifyListeners();
    }, onError: _onStreamError));

    if (isAdmin) {
      _bind(_est.collection('staff'), staff, StaffMember.fromMap);
      _bind(_est.collection('adminRoles'), adminRoles, AdminRole.fromMap);
      _bind(_est.collection('registrations'), registrations,
          Registration.fromMap);
      _bind(_est.collection('residents'), residents, Resident.fromMap);
      // Pendaftaran yang menunggu di perumahan lain yang juga dikelola,
      // agar tidak terlewat saat pengelola sedang membuka perumahan lain.
      _pendingByEstate.clear();
      for (final e in estates) {
        if (e.id == _estateId) continue;
        _subs.add(_db!
            .collection('estates')
            .doc(e.id)
            .collection('registrations')
            .where('status', isEqualTo: RegistrationStatus.menunggu.name)
            .snapshots()
            .listen((snap) {
          _pendingByEstate[e.id] = snap.size;
          notifyListeners();
        }, onError: _onStreamError));
      }
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
    _bind(scoped('members'), members, HouseholdMember.fromMap);
    if (!isAdmin && currentUser!.isPrimary) {
      // Kepala keluarga: permintaan gabung ke rumahnya.
      _bind(
          _est
              .collection('registrations')
              .where('kind', isEqualTo: RegistrationKind.gabung.name)
              .where('residentId', isEqualTo: rid),
          registrations,
          Registration.fromMap);
    }
    _bind(scoped('bills'), bills, Bill.fromMap);
    _bind(scoped('payments'), payments, Payment.fromMap);
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
      // Satu dokumen rusak/tidak lengkap (mis. diubah manual di Console)
      // tidak boleh menyembunyikan dokumen lain: lewati & catat saja.
      final items = <T>[];
      for (final d in snap.docs) {
        try {
          items.add(parse(d.id, d.data()));
        } catch (e) {
          debugPrint('Dokumen ${d.reference.path} dilewati: $e');
          _reportProblem('Dokumen ${d.reference.path} tidak bisa dibaca: $e');
        }
      }
      target
        ..clear()
        ..addAll(items);
      notifyListeners();
    }, onError: _onStreamError));
  }

  void _onStreamError(Object e) {
    debugPrint('Firestore stream error: $e');
    _reportProblem('Gagal memuat data: $e');
  }

  /// Masalah saat memuat data (ditolak aturan keamanan, dokumen rusak).
  /// Ditampilkan ke pengelola agar mudah dilacak.
  final List<String> syncProblems = [];

  void _reportProblem(String message) {
    if (syncProblems.contains(message)) return;
    syncProblems.add(message);
    if (syncProblems.length > 20) syncProblems.removeAt(0);
    notifyListeners();
  }

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
    _pendingByEstate.clear();
    members.clear();
    staff.clear();
    adminRoles.clear();
    payments.clear();
    bankAccounts.clear();
    bills.clear();
    complaints.clear();
    visitors.clear();
    announcements.clear();
  }

  // ---------- Sesi ----------

  bool get isAdmin => currentUser?.role == Role.pengelola;

  // ---------- Hak akses pengelola ----------

  /// Mode demo: anggota tim yang sedang login (null = pemilik contoh).
  String? _demoStaffId;

  String? get _myUid => isFirebase ? _auth!.currentUser?.uid : _demoStaffId;

  /// Data tim milik pengguna ini di perumahan aktif. Null untuk pemilik lama
  /// (pengelola yang belum tercatat di tim dianggap pemilik).
  StaffMember? get myStaff {
    final uid = _myUid;
    if (uid == null) return null;
    return staff.where((m) => m.id == uid).firstOrNull;
  }

  /// Pemilik: akses penuh & satu-satunya yang mengatur tim/level akses.
  /// Pengelola yang tidak tercatat di tim perumahan ini dianggap pemilik
  /// (akun pengelola lama), sama seperti di aturan keamanan.
  bool get isOwner {
    if (!isAdmin) return false;
    final m = myStaff;
    if (m != null) return m.isOwner;
    return isFirebase || _demoStaffId == null;
  }

  Set<AdminPermission> get permissions => !isAdmin
      ? const {}
      : isOwner
          ? AdminPermission.values.toSet()
          : (myStaff?.permissions ?? const {});

  int get _ownerCount => staff.where((m) => m.isOwner).length;

  bool can(AdminPermission p) => permissions.contains(p);

  void _require(AdminPermission p) {
    if (!isAdmin) throw StateError('Hanya pengelola yang bisa melakukan ini.');
    if (!can(p)) {
      throw StateError('Anda tidak punya akses "${p.label}". Hubungi pemilik.');
    }
  }

  void _requireOwner() {
    if (!isOwner) {
      throw StateError('Hanya pemilik yang bisa mengatur tim & level akses.');
    }
  }

  AdminRole? adminRoleById(String? id) =>
      id == null ? null : adminRoles.where((r) => r.id == id).firstOrNull;

  /// Membuat / mengubah level akses. Anggota tim dengan level ini ikut
  /// diperbarui hak aksesnya.
  Future<void> saveAdminRole(String name, Set<AdminPermission> perms,
      {String? id}) async {
    _requireOwner();
    if (name.trim().isEmpty) throw StateError('Nama level wajib diisi.');
    if (perms.isEmpty) throw StateError('Pilih minimal satu hak akses.');
    _checkName(name, adminRoles.where((r) => r.id != id).map((r) => r.name),
        'Level akses');
    final users = staff.where((m) => id != null && m.roleId == id).toList();
    if (!isFirebase) {
      if (id == null) {
        adminRoles.add(AdminRole(id: _newId('L'), name: name, permissions: perms));
      } else {
        adminRoleById(id)!
          ..name = name
          ..permissions = perms;
        for (final m in users) {
          m
            ..roleName = name
            ..permissions = perms;
        }
      }
      notifyListeners();
      return;
    }
    final ref = id == null
        ? _est.collection('adminRoles').doc()
        : _est.collection('adminRoles').doc(id);
    final permList = [for (final p in perms) p.name]..sort();
    final batch = _db!.batch()..set(ref, {'name': name, 'permissions': permList});
    for (final m in users) {
      batch.update(_est.collection('staff').doc(m.id),
          {'roleName': name, 'permissions': permList});
    }
    await batch.commit();
  }

  Future<void> deleteAdminRole(String id) async {
    _requireOwner();
    final used = staff.where((m) => m.roleId == id && !m.isOwner).length;
    if (used > 0) throw StateError('Level ini masih dipakai $used anggota tim.');
    if (!isFirebase) {
      adminRoles.removeWhere((r) => r.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('adminRoles').doc(id).delete();
  }

  /// Menambah anggota tim pengelola. [roleId] null = pemilik.
  /// Mode Firebase: mengembalikan password sementara bila akun baru dibuat
  /// (null bila email sudah punya akun pengelola).
  /// Mode demo: data perumahan yang sedang tidak aktif (dibuat bila belum).
  _DemoEstate _demoSnapshot(String id) => _demoEstates.putIfAbsent(
      id, () => _DemoEstate.empty(estateNameOf(id)));

  List<StaffMember> _staffListOf(String estateId) =>
      estateId == _estateId ? staff : _demoSnapshot(estateId).staff;

  /// Perumahan yang bisa diakses anggota tim [m].
  List<String> staffEstateIds(StaffMember m) {
    if (m.allEstates) return [for (final e in estates) e.id];
    if (isFirebase) {
      final known = [
        for (final e in estates)
          if (m.estateIds.contains(e.id)) e.id,
      ];
      return known.isEmpty ? [if (_estateId != null) _estateId!] : known;
    }
    return [
      for (final e in estates)
        if ((e.id == _estateId
                ? staff
                : _demoEstates[e.id]?.staff ?? const <StaffMember>[])
            .any((x) => x.id == m.id))
          e.id,
    ];
  }

  String staffEstatesLabel(StaffMember m) {
    if (m.allEstates) return 'Semua perumahan';
    final ids = staffEstateIds(m);
    return ids.length == 1 ? estateNameOf(ids.first) : '${ids.length} perumahan';
  }

  /// Target perumahan: semua, atau daftar terpilih (minimal satu).
  List<String> _staffTargets(List<String>? estateIds, bool allEstates) {
    final all = [for (final e in estates) e.id];
    final targets = allEstates
        ? all
        : [for (final id in (estateIds ?? [_estateId!])) if (all.contains(id)) id];
    if (targets.isEmpty) throw StateError('Pilih minimal satu perumahan.');
    return targets;
  }

  /// Mode demo: salin anggota (dan levelnya) ke perumahan [estateId].
  void _demoPutStaff(String estateId, StaffMember src, AdminRole? role) {
    final list = _staffListOf(estateId);
    list.removeWhere((x) => x.id == src.id);
    list.add(StaffMember(
      id: src.id,
      name: src.name,
      email: src.email,
      phone: src.phone,
      isOwner: src.isOwner,
      roleId: src.roleId,
      roleName: src.roleName,
      permissions: src.permissions,
      allEstates: src.allEstates,
    ));
    if (role != null) {
      final roles =
          estateId == _estateId ? adminRoles : _demoSnapshot(estateId).adminRoles;
      if (!roles.any((r) => r.id == role.id)) {
        roles.add(AdminRole(
            id: role.id, name: role.name, permissions: {...role.permissions}));
      }
    }
  }

  /// Pemilik menambah anggota tim ke satu/beberapa/semua perumahan.
  /// Level akses diambil dari perumahan aktif dan disalin ke perumahan lain.
  Future<String?> addStaff({
    required String name,
    required String email,
    String phone = '',
    String? roleId,
    List<String>? estateIds,
    bool allEstates = false,
  }) async {
    _requireOwner();
    final role = adminRoleById(roleId);
    if (roleId != null && role == null) throw StateError('Level tidak ditemukan.');
    final mail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      throw StateError('Email tidak valid.');
    }
    if (staff.any((m) => m.email.toLowerCase() == mail)) {
      throw StateError('$mail sudah ada di tim.');
    }
    final targets = _staffTargets(estateIds, allEstates);
    if (!isFirebase) {
      final m = StaffMember(
        id: _newId('S'),
        name: name.trim(),
        email: mail,
        phone: phone.trim(),
        isOwner: role == null,
        roleId: role?.id,
        roleName: role?.name ?? '',
        permissions: role?.permissions ?? const {},
        allEstates: allEstates,
      );
      for (final id in targets) {
        _demoPutStaff(id, m, role);
      }
      notifyListeners();
      return null;
    }
    final res = await _fn!.httpsCallable('addStaff').call<Map<String, dynamic>>({
      'estateId': _estateId,
      'estateIds': targets,
      'allEstates': allEstates,
      'name': name.trim(),
      'email': mail,
      'phone': phone.trim(),
      'roleId': roleId,
    });
    return res.data['tempPassword'] as String?;
  }

  /// Pemilik membuat password sementara baru untuk anggota tim.
  Future<({String email, String tempPassword})> resetStaffPassword(
      String uid) async {
    _requireOwner();
    if (uid == _myUid) {
      throw StateError('Gunakan menu Ganti password untuk akun sendiri.');
    }
    if (!staff.any((m) => m.id == uid)) {
      throw StateError('Anggota tim tidak ditemukan.');
    }
    if (!isFirebase) {
      throw StateError('Reset password hanya tersedia di mode Firebase.');
    }
    final res = await _fn!
        .httpsCallable('resetStaffPassword')
        .call<Map<String, dynamic>>({'estateId': _estateId, 'uid': uid});
    return (
      email: res.data['email'] as String,
      tempPassword: res.data['tempPassword'] as String,
    );
  }

  /// Pemilik mengatur perumahan yang bisa diakses anggota tim.
  Future<void> setStaffEstates(String uid,
      {List<String>? estateIds, bool allEstates = false}) async {
    _requireOwner();
    final m = staff.where((x) => x.id == uid).firstOrNull;
    if (m == null) throw StateError('Anggota tim tidak ditemukan.');
    if (uid == _myUid) {
      throw StateError('Tidak bisa mengubah akses perumahan sendiri.');
    }
    final targets = _staffTargets(estateIds, allEstates);
    if (!targets.contains(_estateId) && m.isOwner && _ownerCount <= 1) {
      throw StateError('Harus ada minimal satu pemilik di perumahan ini.');
    }
    if (!isFirebase) {
      final role = adminRoleById(m.roleId);
      m.allEstates = allEstates;
      for (final e in estates) {
        if (targets.contains(e.id)) {
          _demoPutStaff(e.id, m, role);
        } else {
          _staffListOf(e.id).removeWhere((x) => x.id == uid);
        }
      }
      notifyListeners();
      return;
    }
    await _fn!.httpsCallable('setStaffEstates').call<void>({
      'estateId': _estateId,
      'uid': uid,
      'estateIds': targets,
      'allEstates': allEstates,
    });
  }

  /// Mengganti level akses anggota tim ([roleId] null = jadikan pemilik).
  Future<void> setStaffRole(String uid, String? roleId) async {
    _requireOwner();
    final m = staff.where((m) => m.id == uid).firstOrNull;
    if (m == null) throw StateError('Anggota tim tidak ditemukan.');
    if (uid == _myUid) throw StateError('Tidak bisa mengubah level akses sendiri.');
    final role = adminRoleById(roleId);
    if (roleId != null && role == null) throw StateError('Level tidak ditemukan.');
    if (m.isOwner && role != null && _ownerCount <= 1) {
      throw StateError('Harus ada minimal satu pemilik.');
    }
    if (!isFirebase) {
      m
        ..isOwner = role == null
        ..roleId = role?.id
        ..roleName = role?.name ?? ''
        ..permissions = role?.permissions ?? const {};
      notifyListeners();
      return;
    }
    await _est.collection('staff').doc(uid).update({
      'isOwner': role == null,
      'roleId': role?.id,
      'roleName': role?.name ?? '',
      'permissions': [
        for (final p in role?.permissions ?? const <AdminPermission>{}) p.name
      ]..sort(),
    });
  }

  /// Mengeluarkan anggota tim dari perumahan ini.
  Future<void> removeStaff(String uid) async {
    _requireOwner();
    if (uid == _myUid) throw StateError('Tidak bisa mengeluarkan diri sendiri.');
    final target = staff.where((m) => m.id == uid).firstOrNull;
    if (target != null && target.isOwner && _ownerCount <= 1) {
      throw StateError('Harus ada minimal satu pemilik.');
    }
    if (!isFirebase) {
      staff.removeWhere((m) => m.id == uid);
      notifyListeners();
      return;
    }
    await _fn!.httpsCallable('removeStaff').call<void>({
      'estateId': _estateId,
      'uid': uid,
    });
  }

  Resident? get currentResident {
    final id = currentUser?.residentId;
    return id == null ? null : residentById(id);
  }

  /// Login mode demo. [memberId]: masuk sebagai anggota rumah.
  /// [staffId]: masuk sebagai anggota tim pengelola (null = pemilik).
  void login(Role role,
      {String? residentId, String? memberId, String? staffId}) {
    _demoStaffId = null;
    if (role == Role.pengelola) {
      final m = staff.where((m) => m.id == staffId).firstOrNull;
      _demoStaffId = m?.id;
      currentUser = AppUser(
          name: m?.name ?? 'Pak Hendra', role: Role.pengelola, email: m?.email);
    } else if (memberId != null) {
      final m = memberById(memberId)!;
      currentUser = AppUser(
        name: m.name,
        role: Role.warga,
        residentId: m.residentId,
        email: m.email,
        isPrimary: false,
        relation: m.relation,
      );
    } else {
      final r = residentById(residentId!)!;
      currentUser = AppUser(
          name: r.name, role: Role.warga, residentId: r.id, email: r.email);
    }
    _demoHomes();
    notifyListeners();
  }

  /// Mode demo: rumah lain milik akun yang sama dicari dari data warga di
  /// semua perumahan contoh (email atau No. HP sama).
  void _demoHomes() {
    homes.clear();
    final user = currentUser;
    if (user == null || user.role != Role.warga || user.residentId == null) {
      _activeHomeKey = null;
      return;
    }
    final me = currentResident;
    bool same(Resident r) =>
        r.id == me?.id ||
        (me != null &&
            ((me.email ?? '').isNotEmpty && r.email == me.email ||
                me.phone.isNotEmpty && r.phone == me.phone));
    for (final e in estates) {
      final list = e.id == _estateId
          ? residents
          : _demoEstates[e.id]?.residents ?? const <Resident>[];
      for (final r in list) {
        if (user.isPrimary && same(r) || r.id == user.residentId && e.id == _estateId) {
          homes.add(HomeRef(
            estateId: e.id,
            residentId: r.id,
            label: '${r.houseNo} · ${e.name}',
            isHead: user.isPrimary,
            relation: user.relation,
          ));
        }
      }
    }
    _activeHomeKey = '$_estateId/${user.residentId}';
  }

  /// Rumah-rumah milik akun warga ini (minimal satu).
  final List<HomeRef> homes = [];
  String? _activeHomeKey;

  HomeRef? get activeHome =>
      homes.where((h) => h.key == _activeHomeKey).firstOrNull;

  /// Label rumah untuk ditampilkan, mis. "A1/05 · Griya Asri".
  String homeLabel(HomeRef h) {
    if (h.label.isNotEmpty) return h.label;
    final house = h.key == _activeHomeKey ? currentResident?.houseNo : null;
    final estate = estateNameOf(h.estateId);
    return house == null ? estate : '$house · $estate';
  }

  /// Warga dengan beberapa rumah: pindah rumah aktif. Tagihan, keluhan,
  /// tamu, renovasi, dan pembayaran mengikuti rumah yang dipilih.
  Future<void> switchHome(String key) async {
    final h = homes.where((x) => x.key == key).firstOrNull;
    final user = currentUser;
    if (h == null || user == null || isAdmin) {
      throw StateError('Rumah tidak ditemukan.');
    }
    if (key == _activeHomeKey) return;
    if (!isFirebase) {
      if (h.estateId != _estateId) await switchEstate(h.estateId);
      _activeHomeKey = key;
      currentUser = user.forHome(h);
      notifyListeners();
      return;
    }
    _activeHomeKey = key;
    _estateId = h.estateId;
    currentUser = user.forHome(h);
    _clearData();
    estateName = estateNameOf(h.estateId);
    _listen();
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
    homes.clear();
    _activeHomeKey = null;
    myRegistration = null;
    _demoRegistrantId = null;
    _demoStaffId = null;
    _lastPassword = null;
    if (isFirebase) {
      // Perangkat ini berhenti menerima notifikasi akun yang keluar.
      await PushService.instance.unregister();
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
    _require(AdminPermission.residents);
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

  /// Pengelola mereset password akun warga yang lupa password: kepala
  /// keluarga [residentId], atau anggota rumahnya bila [memberUid] diisi.
  /// Mengembalikan email akun dan password sementara yang baru; sesi login
  /// lama dikeluarkan dan warga wajib mengganti password saat login.
  Future<({String email, String tempPassword})> resetResidentPassword(
      String residentId,
      {String? memberUid}) async {
    _require(AdminPermission.residents);
    if (!isFirebase) {
      throw StateError('Reset password hanya tersedia di mode Firebase.');
    }
    final res = await _fn!
        .httpsCallable('resetResidentPassword')
        .call<Map<String, dynamic>>({
      'estateId': _estateId,
      'residentId': residentId,
      if (memberUid != null) 'memberUid': memberUid,
    });
    return (
      email: res.data['email'] as String? ?? '',
      tempPassword: res.data['tempPassword'] as String,
    );
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
    _require(AdminPermission.renovations);
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
    _require(AdminPermission.renovations);
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
    _require(AdminPermission.renovations);
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
    _require(AdminPermission.renovations);
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
    _require(AdminPermission.renovations);
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
    _require(AdminPermission.renovations);
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
    _require(AdminPermission.renovations);
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
    if (isAdmin) {
      if (!can(AdminPermission.renovationLogs) &&
          !can(AdminPermission.renovations)) {
        _require(AdminPermission.renovationLogs);
      }
    } else if (currentUser?.residentId != r.residentId) {
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

  // ---------- Anggota rumah ----------

  HouseholdMember? memberById(String id) =>
      members.where((m) => m.id == id).firstOrNull;

  List<HouseholdMember> membersOf(String residentId) =>
      members.where((m) => m.residentId == residentId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Pengelola, atau kepala keluarga rumah tersebut.
  bool canManageMembers(String residentId) =>
      can(AdminPermission.residents) ||
      (currentUser?.role == Role.warga &&
          currentUser!.isPrimary &&
          currentUser!.residentId == residentId);

  /// Menambah anggota rumah dengan akun login sendiri. Mode Firebase:
  /// mengembalikan password sementara (wajib diganti saat login pertama).
  Future<String?> addMember({
    required String residentId,
    required String name,
    required MemberRelation relation,
    required String phone,
    required String email,
  }) async {
    if (!canManageMembers(residentId)) {
      throw StateError('Hanya kepala keluarga atau pengelola yang bisa '
          'menambah anggota rumah.');
    }
    if (name.trim().isEmpty) throw StateError('Nama wajib diisi.');
    final mail = email.trim().toLowerCase();
    if (isFirebase && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      throw StateError('Email tidak valid.');
    }
    if (membersOf(residentId).length >= maxHouseholdMembers) {
      throw StateError('Maksimal $maxHouseholdMembers anggota per rumah.');
    }
    if (!isFirebase) {
      if (mail.isNotEmpty &&
          (members.any((m) => m.email == mail) ||
              residents.any((r) => (r.email ?? '').toLowerCase() == mail))) {
        throw StateError('Email sudah dipakai akun lain.');
      }
      members.add(HouseholdMember(
        id: _newId('M'),
        residentId: residentId,
        name: name.trim(),
        relation: relation,
        phone: phone.trim(),
        email: mail,
        createdAt: DateTime.now(),
      ));
      notifyListeners();
      return null;
    }
    final res = await _fn!
        .httpsCallable('addHouseholdMember')
        .call<Map<String, dynamic>>({
      'estateId': _estateId,
      'residentId': residentId,
      'name': name.trim(),
      'relation': relation.name,
      'phone': phone.trim(),
      'email': mail,
    });
    return res.data['tempPassword'] as String?;
  }

  /// Menghapus anggota rumah beserta akun loginnya.
  Future<void> removeMember(String memberId) async {
    final m = memberById(memberId);
    if (m == null) throw StateError('Anggota tidak ditemukan.');
    if (!canManageMembers(m.residentId)) {
      throw StateError('Hanya kepala keluarga atau pengelola yang bisa '
          'menghapus anggota rumah.');
    }
    if (!isFirebase) {
      members.remove(m);
      notifyListeners();
      return;
    }
    await _fn!.httpsCallable('removeHouseholdMember').call<void>({
      'estateId': _estateId,
      'uid': memberId,
    });
  }

  // ---------- Notifikasi ----------

  Future<void> setNotificationPrefs({bool? announcements, bool? bills}) async {
    final a = announcements ?? notifyAnnouncements;
    final b = bills ?? notifyBills;
    if (isFirebase) {
      await _db!.collection('users').doc(_auth!.currentUser!.uid).update({
        'notifPrefs': {'announcements': a, 'bills': b},
      });
    }
    notifyAnnouncements = a;
    notifyBills = b;
    notifyListeners();
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
      };
      // Rumah kosong yang sedang diajukan pendaftar lain (bukan "gabung").
      final pending = {
        for (final g in regs)
          if (g.status == RegistrationStatus.menunggu &&
              !g.isJoin &&
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
            if (!occupied.contains(h.id) && !pending.contains(h.id)) h.id,
        },
        occupied: occupied,
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
    MemberRelation? relation,
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
        relation: relation,
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
      'relation': relation?.name,
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
    MemberRelation? relation,
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
    final occupant = rs.where((r) => r.houseId == houseId).firstOrNull;
    final join = relation != null;
    if (join) {
      // Gabung ke rumah yang sudah berpenghuni sebagai anggota rumah.
      if (occupant == null) {
        throw StateError('Rumah ini masih kosong. Daftar sebagai warga baru.');
      }
      final ms = active ? members : d!.members;
      if (ms.where((m) => m.residentId == occupant.id).length >=
          maxHouseholdMembers) {
        throw StateError('Anggota rumah ini sudah penuh '
            '($maxHouseholdMembers orang).');
      }
    } else {
      final taken = occupant != null ||
          regs.any((g) =>
              g.houseId == houseId &&
              g.status == RegistrationStatus.menunggu &&
              !g.isJoin &&
              g.id != _demoRegistrantId);
      if (taken) {
        throw StateError('Rumah ini sudah berpenghuni atau sedang diajukan.');
      }
    }
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
        kind: join ? RegistrationKind.gabung : RegistrationKind.baru,
        relation: relation,
        residentId: occupant?.id,
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
        ..reviewedAt = null
        ..kind = join ? RegistrationKind.gabung : RegistrationKind.baru
        ..relation = relation
        ..residentId = join ? occupant!.id : null;
    }
    _demoRegistrantId = reg.id;
    myRegistration = reg;
    currentUser = AppUser(name: name, role: Role.pendaftar, email: email);
    notifyListeners();
  }

  Registration? registrationById(String id) =>
      registrations.where((r) => r.id == id).firstOrNull;

  /// Pengelola: semua pendaftaran menunggu. Kepala keluarga: permintaan
  /// gabung ke rumahnya.
  List<Registration> get pendingRegistrations => registrations
      .where((r) =>
          r.status == RegistrationStatus.menunggu && canReviewRegistration(r))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Mode Firebase: jumlah pendaftaran menunggu per perumahan lain.
  final Map<String, int> _pendingByEstate = {};

  /// Pengelola: pendaftaran menunggu di perumahan lain yang dikelola
  /// (selain perumahan aktif), sebagai (perumahan, jumlah).
  List<(EstateInfo, int)> get pendingInOtherEstates {
    if (!isAdmin) return const [];
    final result = <(EstateInfo, int)>[];
    for (final e in estates) {
      if (e.id == _estateId) continue;
      final n = isFirebase
          ? (_pendingByEstate[e.id] ?? 0)
          : (_demoEstates[e.id]?.registrations ?? const <Registration>[])
              .where((r) => r.status == RegistrationStatus.menunggu)
              .length;
      if (n > 0) result.add((e, n));
    }
    return result;
  }

  /// Permintaan gabung ke rumah tertentu yang masih menunggu.
  List<Registration> joinRequestsFor(String residentId) => registrations
      .where((r) =>
          r.isJoin &&
          r.residentId == residentId &&
          r.status == RegistrationStatus.menunggu)
      .toList();

  /// Pengelola memproses semua pendaftaran; kepala keluarga hanya permintaan
  /// gabung ke rumahnya sendiri.
  bool canReviewRegistration(Registration r) =>
      can(AdminPermission.residents) ||
      (r.isJoin && r.residentId != null && canManageMembers(r.residentId!));

  /// Pengelola menyetujui: akun pendaftar menjadi warga di rumah pilihannya.
  Future<void> approveRegistration(String id) async {
    final reg = registrationById(id);
    if (reg == null || reg.status != RegistrationStatus.menunggu) {
      throw StateError('Pendaftaran tidak ditemukan atau sudah diproses.');
    }
    if (!canReviewRegistration(reg)) {
      throw StateError('Anda tidak berhak memproses pendaftaran ini.');
    }
    if (!isFirebase && reg.isJoin) {
      final household = residentById(reg.residentId!);
      if (household == null) throw StateError('Data rumah tidak ditemukan.');
      if (membersOf(household.id).length >= maxHouseholdMembers) {
        throw StateError('Anggota rumah sudah penuh ($maxHouseholdMembers orang).');
      }
      members.add(HouseholdMember(
        id: reg.id,
        residentId: household.id,
        name: reg.name,
        relation: reg.relation ?? MemberRelation.lainnya,
        phone: reg.phone,
        email: reg.email,
        createdAt: DateTime.now(),
      ));
      reg
        ..status = RegistrationStatus.disetujui
        ..reviewedAt = DateTime.now();
      notifyListeners();
      return;
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
    final reg = registrationById(id);
    if (reg == null || reg.status != RegistrationStatus.menunggu) {
      throw StateError('Pendaftaran tidak ditemukan atau sudah diproses.');
    }
    if (!canReviewRegistration(reg)) {
      throw StateError('Anda tidak berhak memproses pendaftaran ini.');
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
    _require(AdminPermission.masterData);
    if (plan.residents.isNotEmpty) _require(AdminPermission.residents);
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
        monthlyFee: t.monthlyFee,
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
                'monthlyFee': t.monthlyFee,
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
    _require(AdminPermission.residents);
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
    _require(AdminPermission.residents);
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
    int billDueDay = defaultBillDueDay,
  }) async {
    _requireOwner();
    _checkName(name, estates.map((e) => e.name), 'Perumahan');
    _checkDueDay(billDueDay);
    String id;
    if (!isFirebase) {
      id = _newId('E');
      estates.add(EstateInfo(id: id, name: name));
      _demoEstates[id] = _DemoEstate.empty(name, address: address, fee: fee)
        ..depositSmall = depositSmall
        ..depositLarge = depositLarge
        ..billDueDay = billDueDay;
      // Anggota tim berakses "semua perumahan" ikut ke perumahan baru.
      final me = myStaff;
      if (me != null) _demoPutStaff(id, me, null);
      for (final m in staff.where((m) => m.allEstates && m.id != me?.id).toList()) {
        _demoPutStaff(id, m, adminRoleById(m.roleId));
      }
    } else {
      final res =
          await _fn!.httpsCallable('createEstate').call<Map<String, dynamic>>({
        'name': name,
        'address': address,
        'monthlyFee': fee,
        'renovationDepositSmall': depositSmall,
        'renovationDepositLarge': depositLarge,
        'billDueDay': billDueDay,
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
    int? billDueDay,
  }) async {
    _require(AdminPermission.masterData);
    final open = registrationOpen ?? this.registrationOpen;
    final dueDay = billDueDay ?? this.billDueDay;
    _checkDueDay(dueDay);
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
      this.billDueDay = dueDay;
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
      'billDueDay': dueDay,
    });
  }

  void _checkDueDay(int day) {
    if (day < 1 || day > 28) {
      throw StateError('Tanggal jatuh tempo harus 1–28.');
    }
  }

  /// Tarif IPL sebuah rumah tangga: tarif tipe rumahnya bila diatur,
  /// selain itu tarif perumahan.
  int feeForResident(Resident r) {
    final h = r.houseId == null ? null : houseById(r.houseId!);
    return (h == null ? null : houseTypeOf(h)?.monthlyFee) ?? fee;
  }

  void _checkName(String name, Iterable<String> existing, String what) {
    final n = name.trim().toLowerCase();
    if (existing.any((e) => e.trim().toLowerCase() == n)) {
      throw StateError('$what "$name" sudah ada.');
    }
  }

  Future<void> saveCluster(String name, {String? id}) async {
    _require(AdminPermission.masterData);
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
    _require(AdminPermission.masterData);
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
      {String? id, int? buildingArea, int? landArea, int? monthlyFee}) async {
    _require(AdminPermission.masterData);
    if (monthlyFee != null && monthlyFee <= 0) {
      throw StateError('Tarif IPL harus lebih dari 0.');
    }
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
            landArea: landArea,
            monthlyFee: monthlyFee));
      } else {
        houseTypeById(id)!
          ..name = name
          ..buildingArea = buildingArea
          ..landArea = landArea
          ..monthlyFee = monthlyFee;
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
      'monthlyFee': monthlyFee,
    });
  }

  Future<void> deleteHouseType(String id) async {
    _require(AdminPermission.masterData);
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
    _require(AdminPermission.masterData);
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
    _require(AdminPermission.masterData);
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
    _require(AdminPermission.masterData);
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
    _require(AdminPermission.masterData);
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

  // ---------- Pembayaran: transfer ke rekening perumahan + kode unik ----------

  Payment? paymentById(String id) =>
      payments.where((p) => p.id == id).firstOrNull;

  /// Tagihan belum dibayar sebuah rumah, terlama di atas.
  List<Bill> unpaidBillsOf(String residentId) => billsForResident(residentId)
      .where((b) => b.status == BillStatus.belumBayar)
      .toList()
    ..sort((a, b) => a.period.compareTo(b.period));

  /// Pembayaran yang masih berjalan untuk sebuah rumah (maks. satu).
  Payment? activePaymentOf(String residentId) {
    final now = DateTime.now();
    return payments
        .where((p) => p.residentId == residentId && p.isActiveOn(now))
        .firstOrNull;
  }

  /// Tagihan ini sedang dalam pembayaran yang belum selesai.
  bool isBillLocked(Bill b) {
    final now = DateTime.now();
    return payments.any((p) => p.isActiveOn(now) && p.billIds.contains(b.id));
  }

  /// Pengelola: pembayaran yang menunggu verifikasi, terlama di atas.
  List<Payment> get paymentsToVerify => payments
      .where((p) => p.status == PaymentStatus.menungguVerifikasi)
      .toList()
    ..sort((a, b) => (a.submittedAt ?? a.createdAt)
        .compareTo(b.submittedAt ?? b.createdAt));

  void _validateBankAccount(BankAccount a) {
    if (a.bankName.trim().isEmpty ||
        a.accountName.trim().isEmpty ||
        !RegExp(r'^[0-9 .-]{5,30}$').hasMatch(a.accountNumber.trim())) {
      throw StateError('Lengkapi nama bank, nomor & nama pemilik rekening.');
    }
    if (a.title.length > 60) throw StateError('Nama rekening maksimal 60 karakter.');
  }

  /// Pengelola (hak tagihan): atur rekening tujuan transfer perumahan.
  Future<void> saveBankAccounts(List<BankAccount> accounts) async {
    _require(AdminPermission.billing);
    if (accounts.length > 5) throw StateError('Maksimal 5 rekening.');
    accounts.forEach(_validateBankAccount);
    if (!isFirebase) {
      bankAccounts
        ..clear()
        ..addAll(accounts);
      notifyListeners();
      return;
    }
    await _est.update({
      'bankAccounts': [for (final a in accounts) a.toMap()],
    });
  }

  /// Warga memilih tagihan yang dibayar. Tagihan terlama harus ikut
  /// (tidak boleh melompati tunggakan). Server membuat kode unik 3 digit
  /// sehingga total transfer berbeda dari rumah lain.
  Future<Payment> createPayment(List<String> billIds) async {
    final rid = currentUser?.residentId;
    if (isAdmin || rid == null) {
      throw StateError('Pembayaran dilakukan oleh warga.');
    }
    if (bankAccounts.isEmpty) {
      throw StateError('Rekening pembayaran belum diatur pengelola.');
    }
    if (billIds.isEmpty) throw StateError('Pilih minimal satu tagihan.');
    if (activePaymentOf(rid) != null) {
      throw StateError('Masih ada pembayaran yang berjalan. Selesaikan atau '
          'batalkan dulu.');
    }
    final unpaid = unpaidBillsOf(rid);
    final selected = billIds.toSet();
    if (!selected.every((id) => unpaid.any((b) => b.id == id))) {
      throw StateError('Tagihan tidak ditemukan atau sudah lunas.');
    }
    // Harus tagihan-tagihan terlama secara berurutan.
    final expected = unpaid.take(selected.length).map((b) => b.id).toSet();
    if (!expected.containsAll(selected)) {
      throw StateError('Tagihan terlama harus dibayar lebih dulu.');
    }
    if (!isFirebase) {
      final now = DateTime.now();
      final used = {
        for (final p in payments)
          if (p.isActiveOn(now)) p.uniqueCode,
      };
      final free = [for (var c = 1; c <= 999; c++) if (!used.contains(c)) c];
      final code = free[_random.nextInt(free.length)];
      final chosen = unpaid.where((b) => selected.contains(b.id)).toList();
      final house = residentById(rid)?.houseNo ?? '';
      final p = Payment(
        id: _newId('PAY'),
        residentId: rid,
        billIds: [for (final b in chosen) b.id],
        periods: [for (final b in chosen) monthKey(b.period)],
        baseAmount: chosen.fold(0, (t, b) => t + b.amount),
        uniqueCode: code,
        reference: paymentReference(house, code),
        houseNo: house,
        residentName: residentById(rid)?.name ?? '',
        createdAt: now,
        expiresAt: now.add(paymentValidity),
      );
      payments.add(p);
      notifyListeners();
      return p;
    }
    final res = await _fn!.httpsCallable('createPayment').call<Map<String, dynamic>>({
      'estateId': _estateId,
      'residentId': rid,
      'billIds': billIds,
    });
    final id = res.data['paymentId'] as String;
    // Tunggu dokumen tiba lewat listener (biasanya instan).
    for (var i = 0; i < 20 && paymentById(id) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return paymentById(id) ??
        Payment.fromMap(id, (res.data['payment'] as Map).cast<String, dynamic>());
  }

  /// Warga mengunggah bukti transfer (juga untuk unggah ulang bila ditolak).
  Future<void> submitPaymentProof(String paymentId, XFile proof) async {
    final p = paymentById(paymentId);
    if (p == null) throw StateError('Pembayaran tidak ditemukan.');
    if (currentUser?.residentId != p.residentId) {
      throw StateError('Ini bukan pembayaran rumah Anda.');
    }
    final now = DateTime.now();
    if (!p.canUploadProofOn(now)) {
      throw StateError(p.statusOn(now) == PaymentStatus.kedaluwarsa
          ? 'Batas waktu transfer sudah lewat. Buat pembayaran baru.'
          : 'Bukti tidak bisa diunggah pada status ini.');
    }
    if (!isFirebase) {
      p
        ..status = PaymentStatus.menungguVerifikasi
        ..proofUrl = proof.path
        ..submittedAt = now
        ..note = '';
      notifyListeners();
      return;
    }
    final ref = _storage!.ref(
        'estates/$_estateId/payments/${p.residentId}/${p.id}/bukti-${now.millisecondsSinceEpoch}.jpg');
    await ref.putData(
        await proof.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
    await _est.collection('payments').doc(p.id).update({
      'status': PaymentStatus.menungguVerifikasi.name,
      'proofUrl': await ref.getDownloadURL(),
      'submittedAt': FieldValue.serverTimestamp(),
      'note': '',
    });
  }

  /// Warga membatalkan pembayaran yang belum diverifikasi (mis. salah pilih
  /// tagihan). Tagihannya bisa dibayar lagi dengan kode baru.
  Future<void> cancelPayment(String paymentId) async {
    final p = paymentById(paymentId);
    if (p == null) throw StateError('Pembayaran tidak ditemukan.');
    if (currentUser?.residentId != p.residentId) {
      throw StateError('Ini bukan pembayaran rumah Anda.');
    }
    if (p.status != PaymentStatus.menungguTransfer &&
        p.status != PaymentStatus.ditolak) {
      throw StateError('Pembayaran ini tidak bisa dibatalkan.');
    }
    if (!isFirebase) {
      p.status = PaymentStatus.dibatalkan;
      notifyListeners();
      return;
    }
    await _est
        .collection('payments')
        .doc(p.id)
        .update({'status': PaymentStatus.dibatalkan.name});
  }

  /// Pengelola (hak tagihan) memverifikasi transfer: semua tagihan di
  /// dalamnya menjadi lunas.
  Future<void> verifyPayment(String paymentId) async {
    _require(AdminPermission.billing);
    final p = paymentById(paymentId);
    if (p == null || p.status != PaymentStatus.menungguVerifikasi) {
      throw StateError('Pembayaran tidak menunggu verifikasi.');
    }
    if (!isFirebase) {
      final now = DateTime.now();
      for (final b in bills.where((b) => p.billIds.contains(b.id))) {
        b
          ..status = BillStatus.lunas
          ..paidAt = now
          ..method = 'Transfer · kode ${p.uniqueCode.toString().padLeft(3, '0')}'
          ..paymentId = p.id;
      }
      p
        ..status = PaymentStatus.diterima
        ..reviewedAt = now
        ..reviewedBy = currentUser?.name ?? '';
      notifyListeners();
      return;
    }
    await _fn!.httpsCallable('verifyPayment').call<void>({
      'estateId': _estateId,
      'paymentId': paymentId,
    });
  }

  /// Bukti tidak valid: warga diminta mengunggah ulang (atau membatalkan).
  Future<void> rejectPayment(String paymentId, String reason) async {
    _require(AdminPermission.billing);
    final p = paymentById(paymentId);
    if (p == null || p.status != PaymentStatus.menungguVerifikasi) {
      throw StateError('Pembayaran tidak menunggu verifikasi.');
    }
    if (reason.trim().isEmpty) throw StateError('Isi alasan penolakan.');
    if (!isFirebase) {
      p
        ..status = PaymentStatus.ditolak
        ..note = reason.trim()
        ..reviewedAt = DateTime.now()
        ..reviewedBy = currentUser?.name ?? '';
      notifyListeners();
      return;
    }
    await _est.collection('payments').doc(p.id).update({
      'status': PaymentStatus.ditolak.name,
      'note': reason.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': currentUser?.name ?? '',
    });
  }

  /// Membuat tagihan bulan berjalan untuk warga yang belum punya.
  /// Mengembalikan jumlah tagihan baru.
  Future<int> generateBillsForCurrentMonth() async {
    _require(AdminPermission.billing);
    final now = DateTime.now();
    final period = DateTime(now.year, now.month);
    final missing = residents
        .where((r) =>
            !bills.any((b) => b.residentId == r.id && b.period == period))
        .toList();
    if (missing.isEmpty) return 0;

    final due = dueDateFor(period, billDueDay);
    if (!isFirebase) {
      for (final r in missing) {
        bills.add(Bill(
            id: _newId('B'),
            residentId: r.id,
            period: period,
            amount: feeForResident(r),
            dueDate: due));
      }
      notifyListeners();
      return missing.length;
    }
    final batch = _db!.batch();
    for (final r in missing) {
      final bill = Bill(
          id: '',
          residentId: r.id,
          period: period,
          amount: feeForResident(r),
          dueDate: due);
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
    _require(AdminPermission.complaints);
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
    _require(AdminPermission.visitors);
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

  /// Pengumuman yang tampil: pengelola melihat semua (termasuk yang sudah
  /// berakhir), warga hanya yang masih berlaku. Terbaru di atas.
  List<Announcement> get visibleAnnouncements {
    final now = DateTime.now();
    return [
      for (final a in announcements)
        if (isAdmin || a.isActiveOn(now)) a
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Announcement? announcementById(String id) =>
      announcements.where((a) => a.id == id).firstOrNull;

  /// Pengelola membuat pengumuman untuk satu atau beberapa perumahan
  /// (default: perumahan aktif), opsional dengan foto & batas berlaku.
  Future<void> addAnnouncement(String title, String body,
      {List<String>? estateIds, DateTime? until, XFile? photo}) async {
    _require(AdminPermission.announcements);
    title = title.trim();
    body = body.trim();
    if (title.isEmpty) throw StateError('Judul wajib diisi.');
    if (title.length > 120) throw StateError('Judul maksimal 120 karakter.');
    if (body.length > 5000) throw StateError('Isi maksimal 5000 karakter.');
    if (until != null && dateOnly(until).isBefore(dateOnly(DateTime.now()))) {
      throw StateError('Tanggal berakhir tidak boleh sebelum hari ini.');
    }
    final all = [for (final e in estates) e.id];
    final targets = [
      for (final id in (estateIds ?? [_estateId!])) if (all.contains(id)) id
    ];
    if (targets.isEmpty) throw StateError('Pilih minimal satu perumahan.');
    final by = currentUser?.name ?? '';
    if (!isFirebase) {
      for (final id in targets) {
        final a = Announcement(
            id: _newId('P'),
            title: title,
            body: body,
            createdAt: DateTime.now(),
            photoUrl: photo?.path,
            until: until == null ? null : dateOnly(until),
            createdBy: by);
        (id == _estateId ? announcements : _demoSnapshot(id).announcements)
            .insert(0, a);
      }
      notifyListeners();
      return;
    }
    String? photoUrl;
    if (photo != null) {
      photoUrl = await _uploadFile(
          'estates/$_estateId/announcements/${DateTime.now().millisecondsSinceEpoch}.jpg',
          photo,
          contentType: 'image/jpeg');
    }
    final batch = _db!.batch();
    for (final id in targets) {
      batch.set(_db!.collection('estates').doc(id).collection('announcements').doc(), {
        'title': title,
        'body': body,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (until != null) 'until': dayKey(until),
        'createdBy': by,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Pengelola (hak pengumuman) menghapus pengumuman.
  Future<void> deleteAnnouncement(String id) async {
    _require(AdminPermission.announcements);
    if (!isFirebase) {
      announcements.removeWhere((a) => a.id == id);
      notifyListeners();
      return;
    }
    await _est.collection('announcements').doc(id).delete();
  }

  /// Nominal deposit ijin renovasi (kecil/ringan & besar/berat). Bisa diatur
  /// pengelola dengan hak master data atau ijin renovasi.
  Future<void> setRenovationDeposits(int small, int large) async {
    if (!can(AdminPermission.renovations) && !can(AdminPermission.masterData)) {
      _require(AdminPermission.renovations);
    }
    if (small <= 0 || large <= 0) {
      throw StateError('Deposit harus lebih dari 0.');
    }
    if (!isFirebase) {
      depositSmall = small;
      depositLarge = large;
      notifyListeners();
      return;
    }
    await _est.update({
      'renovationDepositSmall': small,
      'renovationDepositLarge': large,
    });
  }

  /// Tambah rekening ke satu atau beberapa perumahan sekaligus.
  Future<void> addBankAccount(BankAccount account, List<String> estateIds) async {
    _require(AdminPermission.billing);
    _validateBankAccount(account);
    final targets = [
      for (final e in estates) if (estateIds.contains(e.id)) e.id
    ];
    if (targets.isEmpty) throw StateError('Pilih minimal satu perumahan.');
    if (!isFirebase) {
      for (final id in targets) {
        final list =
            id == _estateId ? bankAccounts : _demoSnapshot(id).bankAccounts;
        if (list.length >= 5) {
          throw StateError('${estateNameOf(id)} sudah punya 5 rekening.');
        }
        list.add(account);
      }
      notifyListeners();
      return;
    }
    final batch = _db!.batch();
    for (final id in targets) {
      batch.update(_db!.collection('estates').doc(id), {
        'bankAccounts': FieldValue.arrayUnion([account.toMap()]),
      });
    }
    await batch.commit();
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

  /// Rekening perumahan & satu pembayaran yang menunggu verifikasi.
  void _seedDemoPayments() {
    bankAccounts.addAll(const [
      BankAccount(
          bankName: 'BCA',
          accountNumber: '123 456 7890',
          accountName: 'Paguyuban Warga Griya Asri'),
      BankAccount(
          bankName: 'Bank Mandiri',
          accountNumber: '137 00 1234567 8',
          accountName: 'Paguyuban Warga Griya Asri'),
    ]);
    // Siti (R2) sudah transfer IPL bulan ini & mengunggah bukti.
    final siti = residentById('R2')!;
    final bill = unpaidBillsOf(siti.id).last;
    final created = DateTime.now().subtract(const Duration(hours: 3));
    payments.add(Payment(
      id: 'PAY-DEMO',
      residentId: siti.id,
      billIds: [bill.id],
      periods: [monthKey(bill.period)],
      baseAmount: bill.amount,
      uniqueCode: 457,
      reference: paymentReference(siti.houseNo, 457),
      houseNo: siti.houseNo,
      residentName: siti.name,
      createdAt: created,
      expiresAt: created.add(paymentValidity),
      status: PaymentStatus.menungguVerifikasi,
      proofUrl: '',
      submittedAt: created.add(const Duration(minutes: 40)),
    ));
  }

  /// Tim pengelola contoh: pemilik + bendahara + satpam, dan 3 level akses.
  void _seedDemoStaff() {
    final bendahara = AdminRole(
        id: 'L-BENDAHARA',
        name: 'Bendahara',
        permissions: {AdminPermission.billing});
    final adminWarga = AdminRole(
        id: 'L-ADMIN-WARGA',
        name: 'Admin Warga',
        permissions: {
          AdminPermission.residents,
          AdminPermission.complaints,
          AdminPermission.announcements,
        });
    final satpam = AdminRole(
        id: 'L-SATPAM',
        name: 'Satpam',
        permissions: {AdminPermission.visitors, AdminPermission.renovationLogs});
    adminRoles.addAll([bendahara, adminWarga, satpam]);
    staff.addAll([
      StaffMember(
          id: 'S-HENDRA',
          name: 'Pak Hendra',
          email: 'hendra@contoh.id',
          isOwner: true),
      StaffMember(
          id: 'S-SARI',
          name: 'Bu Sari',
          email: 'sari.bendahara@contoh.id',
          roleId: bendahara.id,
          roleName: bendahara.name,
          permissions: bendahara.permissions),
      StaffMember(
          id: 'S-JOKO',
          name: 'Pak Joko',
          email: 'joko.satpam@contoh.id',
          roleId: satpam.id,
          roleName: satpam.name,
          permissions: satpam.permissions),
    ]);
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
    // Permintaan gabung ke rumah Budi Santoso (A1/05) sebagai anak.
    final budi = residentById('R1')!;
    registrations.add(Registration(
      id: 'REG-JOIN',
      estateId: _estateId!,
      name: 'Dimas Santoso',
      phone: '0857-1111-2233',
      email: 'dimas.s@contoh.id',
      houseId: budi.houseId!,
      houseNo: budi.houseNo,
      clusterName: clusterById(houseById(budi.houseId!)!.clusterId)?.name ?? '',
      occupancy: Occupancy.keluarga,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      kind: RegistrationKind.gabung,
      relation: MemberRelation.anak,
      residentId: budi.id,
    ));
  }

  /// Perumahan contoh kedua milik pengelola yang sama: master data saja.
  void _seedSecondDemoEstate() {
    final d = _DemoEstate(
      name: 'Amani Residence',
      address: 'Jl. Amani Raya No. 8, Tangerang',
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
    // Budi Santoso juga punya rumah di Amani Residence (satu akun, dua unit).
    final budiHere = Resident(
      id: 'R-AM1',
      name: 'Budi Santoso',
      houseNo: 'M1/08',
      houseId: d.houses.last.id,
      phone: '0812-3456-7890',
    );
    d.residents.add(budiHere);
    final now = DateTime.now();
    d.bills.add(Bill(
      id: _newId('B'),
      residentId: budiHere.id,
      period: DateTime(now.year, now.month),
      amount: d.fee,
    ));
    // Pak Hendra juga pemilik Amani Residence.
    d.staff.add(StaffMember(
        id: 'S-HENDRA',
        name: 'Pak Hendra',
        email: 'hendra@contoh.id',
        isOwner: true));
    _demoEstates['amani-residence'] = d;
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
      EstateInfo(id: 'amani-residence', name: 'Amani Residence'),
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
        final paid = m > 0 ? r.id != 'R3' : i % 3 == 2 && r.id != 'R3';
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
        ..billDueDay = s.billDueDay
        ..registrations.addAll(s.registrations)
        ..members.addAll(s.members)
        ..staff.addAll(s.staff)
        ..adminRoles.addAll(s.adminRoles)
        ..payments.addAll(s.payments)
        ..bankAccounts.addAll(s.bankAccounts);

  final String name;
  final String address;
  final int fee;
  int depositSmall = defaultDepositSmall;
  int depositLarge = defaultDepositLarge;
  bool registrationOpen = true;
  int billDueDay = defaultBillDueDay;
  final registrations = <Registration>[];
  final members = <HouseholdMember>[];
  final staff = <StaffMember>[];
  final adminRoles = <AdminRole>[];
  final payments = <Payment>[];
  final bankAccounts = <BankAccount>[];
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
    s.billDueDay = billDueDay;
    s.registrations.addAll(registrations);
    s.members.addAll(members);
    s.staff.addAll(staff);
    s.adminRoles.addAll(adminRoles);
    s.payments.addAll(payments);
    s.bankAccounts.addAll(bankAccounts);
  }
}
