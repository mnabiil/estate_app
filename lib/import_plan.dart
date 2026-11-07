/// Rencana import master data & warga dari Excel. Dibuat oleh parser
/// (lib/excel_io.dart), ditampilkan sebagai pratinjau, lalu dijalankan oleh
/// `EstateStore.applyImport`.
library;

class PlanType {
  PlanType(this.cluster, this.name, this.buildingArea, this.landArea);
  final String cluster;
  final String name;
  final int? buildingArea;
  final int? landArea;
}

class PlanBlock {
  PlanBlock(this.cluster, this.type, this.name);
  final String cluster;
  final String type;
  final String name;
}

class PlanHouse {
  PlanHouse(this.cluster, this.block, this.number);
  final String cluster;
  final String block;
  final String number;
}

class PlanResident {
  PlanResident({
    required this.name,
    required this.cluster,
    required this.block,
    required this.number,
    required this.phone,
    required this.email,
  });
  final String name;
  final String cluster;
  final String block;
  final String number;
  final String phone;
  final String email;
}

class ImportPlan {
  final clusters = <String>[];
  final types = <PlanType>[];
  final blocks = <PlanBlock>[];
  final houses = <PlanHouse>[];
  final residents = <PlanResident>[];

  /// Data yang sudah ada di perumahan (dilewati, tidak digandakan).
  int existingHouses = 0;
  int existingResidents = 0;

  /// Error membuat import tidak bisa dijalankan; peringatan tidak.
  final errors = <String>[];
  final warnings = <String>[];

  bool get hasErrors => errors.isNotEmpty;
  bool get isEmpty =>
      clusters.isEmpty &&
      types.isEmpty &&
      blocks.isEmpty &&
      houses.isEmpty &&
      residents.isEmpty;
}

/// Hasil pembuatan akun warga (mode Firebase: password sementara).
class ResidentAccount {
  ResidentAccount({
    required this.name,
    required this.house,
    required this.email,
    this.password,
    this.error,
  });
  final String name;
  final String house;
  final String email;
  final String? password;
  final String? error;
}

class ImportResult {
  int clusters = 0;
  int types = 0;
  int blocks = 0;
  int houses = 0;
  int residents = 0;
  final accounts = <ResidentAccount>[];

  int get failedResidents => accounts.where((a) => a.error != null).length;
}

/// Nama dibandingkan tanpa beda huruf besar/kecil & spasi berlebih.
String normName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Nomor rumah dibandingkan tanpa nol di depan: "05" == "5".
String normNumber(String s) {
  final t = normName(s).replaceAll(' ', '');
  final m = RegExp(r'^0+(\d)').firstMatch(t);
  return m == null ? t : t.replaceFirst(RegExp(r'^0+'), '');
}

/// "01-12, 15, 20A" -> ["01".."12", "15", "20A"].
/// Rentang yang diawali nol mempertahankan lebar angka (01, 02, ...).
List<String> expandHouseNumbers(String spec) {
  final out = <String>[];
  for (final raw in spec.split(RegExp(r'[,;]'))) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*[-–—]\s*(\d+)$').firstMatch(token);
    if (m != null) {
      final a = m.group(1)!, b = m.group(2)!;
      final from = int.parse(a), to = int.parse(b);
      if (to < from) {
        throw FormatException('rentang "$token" terbalik');
      }
      if (to - from >= 300) {
        throw FormatException('rentang "$token" lebih dari 300 nomor');
      }
      final width = a.startsWith('0') ? (a.length > b.length ? a.length : b.length) : 0;
      for (var n = from; n <= to; n++) {
        out.add(width > 0 ? n.toString().padLeft(width, '0') : '$n');
      }
    } else {
      if (token.length > 10) {
        throw FormatException('nomor "$token" lebih dari 10 karakter');
      }
      out.add(token);
    }
  }
  return out;
}
