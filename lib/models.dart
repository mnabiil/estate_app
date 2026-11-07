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
