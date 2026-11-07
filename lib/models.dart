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
  });

  final String id;
  String name;
  String houseNo;
  String phone;
  String? email;

  factory Resident.fromMap(String id, Map<String, dynamic> m) => Resident(
        id: id,
        name: m['name'] as String? ?? '',
        houseNo: m['houseNo'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String?,
      );
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
  });

  final String id;
  final String residentId;
  final String title;
  final String description;
  final String category;
  final DateTime createdAt;
  ComplaintStatus status;

  factory Complaint.fromMap(String id, Map<String, dynamic> m) => Complaint(
        id: id,
        residentId: m['residentId'] as String,
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        category: m['category'] as String? ?? 'Lainnya',
        // createdAt bisa null sesaat sebelum server mengisi serverTimestamp.
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        status: ComplaintStatus.values.byName(m['status'] as String? ?? 'baru'),
      );
}

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
