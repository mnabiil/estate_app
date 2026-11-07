import 'package:cloud_firestore/cloud_firestore.dart';

/// `pendaftar`: mendaftar sendiri dan menunggu verifikasi pengelola; belum
/// bisa mengakses data perumahan.
enum Role { warga, pengelola, pendaftar }

class AppUser {
  const AppUser({
    required this.name,
    required this.role,
    this.residentId,
    this.mustChangePassword = false,
    this.email,
    this.isPrimary = true,
    this.relation,
  });

  final String name;
  final Role role;

  /// Rumah tangga (data warga) yang diakses; sama untuk kepala keluarga dan
  /// semua anggota rumah.
  final String? residentId;
  final String? email;

  /// Kepala keluarga (akun utama rumah). Anggota rumah: false.
  final bool isPrimary;

  /// Hubungan anggota dengan kepala keluarga (null untuk kepala keluarga).
  final MemberRelation? relation;

  /// Akun dibuat pengelola dengan password sementara: wajib diganti saat
  /// login pertama.
  final bool mustChangePassword;

  AppUser copyWith({bool? mustChangePassword}) => AppUser(
        name: name,
        role: role,
        residentId: residentId,
        email: email,
        isPrimary: isPrimary,
        relation: relation,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      );
}

/// Aturan password: min. 8 karakter, berisi huruf dan angka.
String? passwordProblem(String password) {
  if (password.length < 8) return 'Minimal 8 karakter';
  if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
      !RegExp(r'\d').hasMatch(password)) {
    return 'Harus berisi huruf dan angka';
  }
  return null;
}

// ---------- Helper serialisasi ----------
// Bulan & tanggal disimpan sebagai teks ("2026-11", "2026-11-06") agar tidak
// bergeser karena zona waktu antara HP dan server.

String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String dayKey(DateTime d) =>
    '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

DateTime parseKey(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p.length > 2 ? p[2] : 1);
}

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

Timestamp? _ts(DateTime? d) => d == null ? null : Timestamp.fromDate(d);

// ---------- Model ----------

class Resident {
  Resident({
    required this.id,
    required this.name,
    required this.houseNo,
    required this.phone,
    this.email,
    this.houseId,
  });

  final String id;
  String name;

  /// Label rumah untuk ditampilkan, mis. "A1/05". Disalin dari master rumah
  /// saat warga ditambahkan (data lama mungkin hanya punya field ini).
  String houseNo;
  String phone;
  String? email;

  /// ID dokumen di master `houses` (null untuk data lama yang diisi manual).
  String? houseId;

  factory Resident.fromMap(String id, Map<String, dynamic> m) => Resident(
        id: id,
        name: m['name'] as String? ?? '',
        houseNo: m['houseNo'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String?,
        houseId: m['houseId'] as String?,
      );
}

// ---------- Master perumahan ----------
//
// Perumahan > Cluster > Tipe rumah > Blok > No. rumah.
// Tipe rumah milik cluster; setiap blok berisi satu tipe; nomor rumah
// mengikuti tipe bloknya.

/// Perumahan yang bisa diakses akun ini (pengelola bisa lebih dari satu).
class EstateInfo {
  EstateInfo({required this.id, required this.name});

  final String id;
  String name;
}

class Cluster {
  Cluster({required this.id, required this.name});

  final String id;
  String name;

  factory Cluster.fromMap(String id, Map<String, dynamic> m) =>
      Cluster(id: id, name: m['name'] as String? ?? '');
}

class HouseBlock {
  HouseBlock({
    required this.id,
    required this.clusterId,
    required this.name,
    this.typeId,
  });

  final String id;
  final String clusterId;
  String name;

  /// Tipe rumah blok ini (null hanya untuk data lama).
  String? typeId;

  factory HouseBlock.fromMap(String id, Map<String, dynamic> m) => HouseBlock(
        id: id,
        clusterId: m['clusterId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        typeId: m['typeId'] as String?,
      );
}

/// Tipe rumah dalam satu cluster, mis. "Tipe 36/72"
/// (luas bangunan 36 m², tanah 72 m²).
class HouseType {
  HouseType({
    required this.id,
    required this.clusterId,
    required this.name,
    this.buildingArea,
    this.landArea,
  });

  final String id;
  final String clusterId;
  String name;
  int? buildingArea;
  int? landArea;

  /// Mis. "LB 36 m² · LT 72 m²", kosong bila luas tidak diisi.
  String get areaText => [
        if (buildingArea != null) 'LB $buildingArea m²',
        if (landArea != null) 'LT $landArea m²',
      ].join(' · ');

  factory HouseType.fromMap(String id, Map<String, dynamic> m) => HouseType(
        id: id,
        clusterId: m['clusterId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        buildingArea: (m['buildingArea'] as num?)?.toInt(),
        landArea: (m['landArea'] as num?)?.toInt(),
      );
}

class House {
  House({
    required this.id,
    required this.clusterId,
    required this.blockId,
    required this.number,
  });

  final String id;
  final String clusterId;
  final String blockId;

  /// Nomor rumah sebagai teks, mis. "05" atau "12A".
  final String number;

  factory House.fromMap(String id, Map<String, dynamic> m) => House(
        id: id,
        clusterId: m['clusterId'] as String? ?? '',
        blockId: m['blockId'] as String? ?? '',
        number: m['number'] as String? ?? '',
      );
}

/// Penanda pilihan "tanpa tipe" untuk blok lama yang belum bertipe.
const noTypeId = '__none__';

/// Urutan alami: "2" < "10" < "10A".
int compareHouseNumber(String a, String b) {
  final na = int.tryParse(RegExp(r'^\d+').stringMatch(a) ?? '');
  final nb = int.tryParse(RegExp(r'^\d+').stringMatch(b) ?? '');
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return a.compareTo(b);
}

enum BillStatus {
  belumBayar('Belum bayar'),
  lunas('Lunas');

  const BillStatus(this.label);
  final String label;
}

class Bill {
  Bill({
    required this.id,
    required this.residentId,
    required this.period,
    required this.amount,
    this.status = BillStatus.belumBayar,
    this.paidAt,
    this.method,
  });

  final String id;
  final String residentId;

  /// Bulan tagihan (tanggal selalu 1).
  final DateTime period;
  final int amount;
  BillStatus status;
  DateTime? paidAt;
  String? method;

  DateTime get dueDate => DateTime(period.year, period.month, 10);

  /// ID dokumen deterministik agar satu warga hanya punya satu tagihan per bulan.
  static String docId(String residentId, DateTime period) =>
      '${residentId}_${monthKey(period)}';

  factory Bill.fromMap(String id, Map<String, dynamic> m) => Bill(
        id: id,
        residentId: m['residentId'] as String,
        period: parseKey(m['period'] as String),
        amount: (m['amount'] as num).toInt(),
        status:
            BillStatus.values.byName(m['status'] as String? ?? 'belumBayar'),
        paidAt: _date(m['paidAt']),
        method: m['method'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'residentId': residentId,
        'period': monthKey(period),
        'amount': amount,
        'status': status.name,
        'paidAt': _ts(paidAt),
        'method': method,
      };
}

enum ComplaintStatus {
  baru('Baru'),
  diproses('Diproses'),
  selesai('Selesai');

  const ComplaintStatus(this.label);
  final String label;
}

const complaintCategories = ['Kebersihan', 'Keamanan', 'Fasilitas', 'Lainnya'];

class Complaint {
  Complaint({
    required this.id,
    required this.residentId,
    required this.title,
    required this.description,
    required this.category,
    required this.createdAt,
    this.status = ComplaintStatus.baru,
    this.photos = const [],
  });

  final String id;
  final String residentId;
  final String title;
  final String description;
  final String category;
  final DateTime createdAt;
  ComplaintStatus status;

  /// Foto pendukung. Mode Firebase: URL unduhan Firebase Storage.
  /// Mode demo: path file lokal di perangkat.
  final List<String> photos;

  factory Complaint.fromMap(String id, Map<String, dynamic> m) => Complaint(
        id: id,
        residentId: m['residentId'] as String,
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        category: m['category'] as String? ?? 'Lainnya',
        // createdAt bisa null sesaat sebelum server mengisi serverTimestamp.
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        status: ComplaintStatus.values.byName(m['status'] as String? ?? 'baru'),
        photos: (m['photoUrls'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );
}

/// Batas jumlah foto per keluhan (sama dengan firestore.rules & storage.rules).
const maxComplaintPhotos = 3;

class Visitor {
  Visitor({
    required this.id,
    required this.residentId,
    required this.name,
    required this.purpose,
    required this.visitDate,
    required this.code,
    this.checkedInAt,
  });

  final String id;
  final String residentId;
  final String name;
  final String purpose;
  final DateTime visitDate;

  /// Kode akses yang ditunjukkan tamu ke satpam.
  final String code;
  DateTime? checkedInAt;

  factory Visitor.fromMap(String id, Map<String, dynamic> m) => Visitor(
        id: id,
        residentId: m['residentId'] as String,
        name: m['name'] as String? ?? '',
        purpose: m['purpose'] as String? ?? '',
        visitDate: parseKey(m['visitDate'] as String),
        code: m['code'] as String? ?? '',
        checkedInAt: _date(m['checkedInAt']),
      );

  Map<String, dynamic> toMap() => {
        'residentId': residentId,
        'name': name,
        'purpose': purpose,
        'visitDate': dayKey(visitDate),
        'code': code,
        'checkedInAt': _ts(checkedInAt),
      };
}

class Announcement {
  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  factory Announcement.fromMap(String id, Map<String, dynamic> m) =>
      Announcement(
        id: id,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
      );
}

// ---------- Ijin renovasi ----------

/// Tanggal tanpa jam. Tanggal renovasi disimpan sebagai "YYYY-MM-DD"
/// lewat [dayKey] / [parseKey].
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

enum RenovationType {
  kecil(
    'Renovasi kecil',
    'Pengecatan, ganti keramik, perbaikan ringan tanpa mengubah struktur '
        'dan tampak depan bangunan.',
  ),
  besar(
    'Renovasi besar',
    'Tambah ruang/lantai, ubah struktur, fasad, atau pagar; pekerjaan '
        'berat dengan material dalam jumlah besar.',
  );

  const RenovationType(this.label, this.description);
  final String label;
  final String description;
}

enum RenovationStatus {
  diajukan('Menunggu persetujuan'),
  disetujui('Disetujui'),
  ditolak('Ditolak'),
  selesai('Selesai'),
  dibatalkan('Dibatalkan');

  const RenovationStatus(this.label);
  final String label;
}

enum DepositStatus {
  belumBayar('Belum dibayar'),
  menungguVerifikasi('Menunggu verifikasi'),
  dibayar('Diterima pengelola'),
  dikembalikan('Dikembalikan');

  const DepositStatus(this.label);
  final String label;
}

/// Tahap pekerjaan untuk renovasi yang sudah disetujui (dihitung dari tanggal).
enum RenovationPhase { belumMulai, berjalan, terlambat }

class Renovation {
  Renovation({
    required this.id,
    required this.residentId,
    required this.type,
    required this.description,
    required this.contractor,
    required this.startDate,
    required this.endDate,
    required this.deposit,
    required this.createdAt,
    this.contractorPhone = '',
    this.status = RenovationStatus.diajukan,
    this.depositStatus = DepositStatus.belumBayar,
    this.attachments = const [],
    this.depositMethod,
    this.depositProofUrl,
    this.depositSubmittedAt,
    this.depositPaidAt,
    this.depositRefund,
    this.depositRefundedAt,
    this.adminNote = '',
  });

  final String id;
  final String residentId;
  final RenovationType type;
  final String description;

  /// Nama kontraktor / mandor yang bekerja.
  final String contractor;
  final String contractorPhone;

  /// Jangka waktu pekerjaan (tanggal saja, inklusif).
  final DateTime startDate;
  DateTime endDate;

  /// Besar deposit sesuai jenis renovasi saat diajukan.
  final int deposit;
  final DateTime createdAt;

  RenovationStatus status;
  DepositStatus depositStatus;

  /// Lampiran pengajuan (gambar desain, denah, RAB, dll.).
  final List<RenovationAttachment> attachments;

  /// Pembayaran deposit oleh warga (setelah ijin disetujui).
  String? depositMethod;

  /// Foto bukti transfer (URL Storage, atau path lokal di mode demo).
  String? depositProofUrl;
  DateTime? depositSubmittedAt;
  DateTime? depositPaidAt;

  /// Jumlah deposit yang dikembalikan (bisa dipotong bila ada pelanggaran).
  int? depositRefund;
  DateTime? depositRefundedAt;

  /// Catatan pengelola (alasan tolak, potongan deposit, dll.).
  String adminNote;

  /// Lama pekerjaan dalam hari (inklusif).
  int get durationDays => endDate.difference(startDate).inDays + 1;

  /// Pekerjaan boleh berjalan: ijin disetujui dan deposit sudah diterima.
  bool get canWork =>
      status == RenovationStatus.disetujui &&
      depositStatus == DepositStatus.dibayar;

  /// Disetujui tetapi deposit belum diterima pengelola.
  bool get awaitingDeposit =>
      status == RenovationStatus.disetujui &&
      depositStatus != DepositStatus.dibayar;

  /// Hanya bermakna bila status disetujui.
  RenovationPhase phaseOn(DateTime today) {
    final d = dateOnly(today);
    if (d.isBefore(startDate)) return RenovationPhase.belumMulai;
    if (d.isAfter(endDate)) return RenovationPhase.terlambat;
    return RenovationPhase.berjalan;
  }

  /// Masih aktif (perlu dipantau): diajukan atau disetujui.
  bool get isActive =>
      status == RenovationStatus.diajukan ||
      status == RenovationStatus.disetujui;

  factory Renovation.fromMap(String id, Map<String, dynamic> m) => Renovation(
        id: id,
        residentId: m['residentId'] as String,
        type: RenovationType.values.byName(m['type'] as String? ?? 'kecil'),
        description: m['description'] as String? ?? '',
        contractor: m['contractor'] as String? ?? '',
        contractorPhone: m['contractorPhone'] as String? ?? '',
        startDate: parseKey(m['startDate'] as String),
        endDate: parseKey(m['endDate'] as String),
        deposit: (m['deposit'] as num?)?.toInt() ?? 0,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        status: RenovationStatus.values
            .byName(m['status'] as String? ?? 'diajukan'),
        depositStatus: DepositStatus.values
            .byName(m['depositStatus'] as String? ?? 'belumBayar'),
        attachments: [
          for (final a in (m['attachments'] as List<dynamic>? ?? const []))
            if (a is Map) RenovationAttachment.fromMap(a.cast<String, dynamic>()),
        ],
        depositMethod: m['depositMethod'] as String?,
        depositProofUrl: m['depositProofUrl'] as String?,
        depositSubmittedAt: _date(m['depositSubmittedAt']),
        depositPaidAt: _date(m['depositPaidAt']),
        depositRefund: (m['depositRefund'] as num?)?.toInt(),
        depositRefundedAt: _date(m['depositRefundedAt']),
        adminNote: m['adminNote'] as String? ?? '',
      );
}

enum LogDirection {
  masuk('Masuk'),
  keluar('Keluar');

  const LogDirection(this.label);
  final String label;
}

/// Catatan barang masuk / keluar selama renovasi.
class RenovationLog {
  RenovationLog({
    required this.id,
    required this.renovationId,
    required this.residentId,
    required this.direction,
    required this.item,
    required this.quantity,
    required this.at,
    required this.recordedBy,
    this.note = '',
    this.photos = const [],
  });

  final String id;
  final String renovationId;
  final String residentId;
  final LogDirection direction;

  /// Nama barang, mis. "Semen".
  final String item;

  /// Jumlah + satuan, mis. "20 sak".
  final String quantity;
  final String note;
  final DateTime at;

  /// Nama pencatat (pengelola/satpam atau warga).
  final String recordedBy;

  /// Foto barang (URL Storage, atau path lokal di mode demo).
  final List<String> photos;

  factory RenovationLog.fromMap(String id, Map<String, dynamic> m) =>
      RenovationLog(
        id: id,
        renovationId: m['renovationId'] as String,
        residentId: m['residentId'] as String,
        direction:
            LogDirection.values.byName(m['direction'] as String? ?? 'masuk'),
        item: m['item'] as String? ?? '',
        quantity: m['quantity'] as String? ?? '',
        note: m['note'] as String? ?? '',
        at: _date(m['at']) ?? DateTime.now(),
        recordedBy: m['recordedBy'] as String? ?? '',
        photos: (m['photoUrls'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );
}

/// Lampiran pengajuan renovasi.
class RenovationAttachment {
  const RenovationAttachment({
    required this.name,
    required this.url,
    this.size = 0,
  });

  final String name;

  /// URL Storage, atau path lokal di mode demo (kosong untuk data contoh).
  final String url;
  final int size;

  bool get isImage {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp') ||
        n.endsWith('.heic');
  }

  Map<String, dynamic> toMap() => {'name': name, 'url': url, 'size': size};

  factory RenovationAttachment.fromMap(Map<String, dynamic> m) =>
      RenovationAttachment(
        name: m['name'] as String? ?? 'lampiran',
        url: m['url'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
      );
}

/// Batas lampiran & foto renovasi (sama dengan firestore/storage rules).
const maxRenovationAttachments = 5;
const maxAttachmentBytes = 10 * 1024 * 1024;
const maxLogPhotos = 3;
const allowedAttachmentExtensions = [
  'pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic', 'doc', 'docx', 'xls', 'xlsx',
];

/// "1,2 MB" / "350 KB".
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// Deposit default bila belum diatur di profil perumahan.
const defaultDepositSmall = 1000000;
const defaultDepositLarge = 5000000;


// ---------- Registrasi mandiri warga ----------

enum Occupancy {
  pemilik('Pemilik'),
  penyewa('Penyewa'),
  keluarga('Keluarga pemilik');

  const Occupancy(this.label);
  final String label;
}

enum RegistrationStatus {
  menunggu('Menunggu verifikasi'),
  disetujui('Disetujui'),
  ditolak('Ditolak');

  const RegistrationStatus(this.label);
  final String label;
}

/// Pendaftaran warga baru. ID dokumen = uid akun pendaftar.
class Registration {
  Registration({
    required this.id,
    required this.estateId,
    required this.name,
    required this.phone,
    required this.email,
    required this.houseId,
    required this.houseNo,
    required this.occupancy,
    required this.createdAt,
    this.clusterName = '',
    this.docUrl,
    this.status = RegistrationStatus.menunggu,
    this.note = '',
    this.reviewedAt,
  });

  final String id;
  final String estateId;
  String name;
  String phone;
  final String email;
  String houseId;
  String houseNo;
  String clusterName;
  Occupancy occupancy;

  /// Foto KTP / bukti hunian (opsional).
  String? docUrl;
  RegistrationStatus status;

  /// Alasan penolakan dari pengelola.
  String note;
  DateTime createdAt;
  DateTime? reviewedAt;

  factory Registration.fromMap(String id, Map<String, dynamic> m) =>
      Registration(
        id: id,
        estateId: m['estateId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        houseId: m['houseId'] as String? ?? '',
        houseNo: m['houseNo'] as String? ?? '',
        clusterName: m['clusterName'] as String? ?? '',
        occupancy:
            Occupancy.values.byName(m['occupancy'] as String? ?? 'pemilik'),
        docUrl: m['docUrl'] as String?,
        status: RegistrationStatus.values
            .byName(m['status'] as String? ?? 'menunggu'),
        note: m['note'] as String? ?? '',
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        reviewedAt: _date(m['reviewedAt']),
      );
}

/// Perumahan yang membuka pendaftaran mandiri.
class RegistrationEstate {
  const RegistrationEstate(
      {required this.id, required this.name, this.address = ''});
  final String id;
  final String name;
  final String address;
}

/// Pilihan rumah untuk calon warga (master data + ketersediaan rumah).
class RegistrationOptions {
  RegistrationOptions({
    required this.clusters,
    required this.types,
    required this.blocks,
    required this.houses,
    required this.available,
  });

  final List<Cluster> clusters;
  final List<HouseType> types;
  final List<HouseBlock> blocks;
  final List<House> houses;

  /// ID rumah yang kosong dan tidak sedang diajukan pendaftar lain.
  final Set<String> available;

  List<Cluster> get sortedClusters =>
      clusters.toList()..sort((a, b) => a.name.compareTo(b.name));

  List<HouseType> typesOf(String clusterId) =>
      types.where((t) => t.clusterId == clusterId).toList()
        ..sort((a, b) => (a.buildingArea ?? 0).compareTo(b.buildingArea ?? 0));

  List<HouseBlock> blocksOf(String clusterId, String typeId) => blocks
      .where((b) => b.clusterId == clusterId && b.typeId == typeId)
      .toList()
    ..sort((a, b) => compareHouseNumber(a.name, b.name));

  List<House> housesOf(String blockId) =>
      houses.where((h) => h.blockId == blockId).toList()
        ..sort((a, b) => compareHouseNumber(a.number, b.number));

  int freeIn(Iterable<House> hs) => hs.where((h) => available.contains(h.id)).length;

  String labelOf(House h) {
    final b = blocks.where((b) => b.id == h.blockId).firstOrNull;
    return '${b?.name ?? '?'}/${h.number}';
  }

  factory RegistrationOptions.fromMap(Map<String, dynamic> m) {
    List<Map<String, dynamic>> list(String k) => [
          for (final e in (m[k] as List<dynamic>? ?? const []))
            (e as Map).cast<String, dynamic>(),
        ];
    return RegistrationOptions(
      clusters: [for (final e in list('clusters')) Cluster.fromMap(e['id'] as String, e)],
      types: [for (final e in list('types')) HouseType.fromMap(e['id'] as String, e)],
      blocks: [for (final e in list('blocks')) HouseBlock.fromMap(e['id'] as String, e)],
      houses: [for (final e in list('houses')) House.fromMap(e['id'] as String, e)],
      available: {
        for (final e in list('houses'))
          if (e['available'] == true) e['id'] as String,
      },
    );
  }
}


// ---------- Anggota rumah (keluarga / penyewa) ----------

enum MemberRelation {
  pasangan('Suami / Istri'),
  anak('Anak'),
  orangTua('Orang tua'),
  saudara('Saudara'),
  penyewa('Penyewa'),
  lainnya('Lainnya (ART, dll.)');

  const MemberRelation(this.label);
  final String label;
}

/// Maksimal anggota (di luar kepala keluarga) per rumah.
const maxHouseholdMembers = 6;

/// Akun tambahan yang berbagi data satu rumah. ID = uid akun anggota.
class HouseholdMember {
  HouseholdMember({
    required this.id,
    required this.residentId,
    required this.name,
    required this.relation,
    required this.createdAt,
    this.phone = '',
    this.email = '',
  });

  final String id;
  final String residentId;
  final String name;
  final MemberRelation relation;
  final String phone;
  final String email;
  final DateTime createdAt;

  factory HouseholdMember.fromMap(String id, Map<String, dynamic> m) =>
      HouseholdMember(
        id: id,
        residentId: m['residentId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        relation: MemberRelation.values
            .byName(m['relation'] as String? ?? 'lainnya'),
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
      );
}
