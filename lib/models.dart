import 'package:cloud_firestore/cloud_firestore.dart';

enum Role { warga, pengelola }

class AppUser {
  const AppUser({required this.name, required this.role, this.residentId});

  final String name;
  final Role role;
  final String? residentId;
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

/// "2026-11-07" — tanggal tanpa jam (aman dari pergeseran zona waktu).
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

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
  DateTime? depositPaidAt;

  /// Jumlah deposit yang dikembalikan (bisa dipotong bila ada pelanggaran).
  int? depositRefund;
  DateTime? depositRefundedAt;

  /// Catatan pengelola (alasan tolak, potongan deposit, dll.).
  String adminNote;

  /// Lama pekerjaan dalam hari (inklusif).
  int get durationDays => endDate.difference(startDate).inDays + 1;

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
        startDate: parseDay(m['startDate'] as String),
        endDate: parseDay(m['endDate'] as String),
        deposit: (m['deposit'] as num?)?.toInt() ?? 0,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        status: RenovationStatus.values
            .byName(m['status'] as String? ?? 'diajukan'),
        depositStatus: DepositStatus.values
            .byName(m['depositStatus'] as String? ?? 'belumBayar'),
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
      );
}

/// Deposit default bila belum diatur di profil perumahan.
const defaultDepositSmall = 1000000;
const defaultDepositLarge = 5000000;
