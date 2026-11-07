/// Baca/tulis file Excel (.xlsx) untuk import & export master data.
///
/// Paket `excel` punya kelas `TextSpan`/`Border` sendiri, jadi diimpor dengan
/// awalan `xl` dan file ini tidak memakai widget Flutter.
library;

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import 'import_plan.dart';
import 'models.dart';
import 'store.dart';

const sheetRumah = 'Rumah';
const sheetWarga = 'Warga';
const sheetPetunjuk = 'Petunjuk';

const _rumahHeader = [
  'Cluster',
  'Tipe',
  'Luas Bangunan (m2)',
  'Luas Tanah (m2)',
  'Tarif IPL (Rp, opsional)',
  'Blok',
  'No. Rumah',
];
const _wargaHeader = [
  'Nama',
  'Cluster',
  'Blok',
  'No. Rumah',
  'No. HP',
  'Email',
];

// ---------------------------------------------------------------------------
// Menulis
// ---------------------------------------------------------------------------

final _headerStyle = xl.CellStyle(
  bold: true,
  backgroundColorHex: xl.ExcelColor.fromHexString('FFD7E8C2'),
);

xl.CellValue _v(Object? v) => switch (v) {
      int i => xl.IntCellValue(i),
      _ => xl.TextCellValue(v?.toString() ?? ''),
    };

void _writeSheet(xl.Sheet sheet, List<String> header, List<List<Object?>> rows,
    {List<double>? widths}) {
  for (var c = 0; c < header.length; c++) {
    sheet.updateCell(
      xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      xl.TextCellValue(header[c]),
      cellStyle: _headerStyle,
    );
    sheet.setColumnWidth(c, widths != null && c < widths.length ? widths[c] : 18);
  }
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      sheet.updateCell(
        xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        _v(rows[r][c]),
      );
    }
  }
}

Uint8List _workbook(Map<String, (List<String>, List<List<Object?>>)> sheets) {
  final book = xl.Excel.createExcel();
  final first = book.getDefaultSheet() ?? 'Sheet1';
  var renamed = false;
  sheets.forEach((name, data) {
    if (!renamed) {
      book.rename(first, name);
      renamed = true;
    }
    _writeSheet(book[name], data.$1, data.$2);
  });
  book.setDefaultSheet(sheets.keys.first);
  return Uint8List.fromList(book.encode()!);
}

const _petunjuk = [
  ['Cara mengisi'],
  ['1. Sheet "Rumah": satu baris per blok. Kolom No. Rumah boleh berisi '
      'rentang (01-20), daftar (1, 2, 5), atau nomor khusus (12A).'],
  ['   Rentang yang diawali nol (01-20) menghasilkan 01, 02, ... 20.'],
  ['2. Tipe rumah milik cluster. Satu blok berisi satu tipe. Tarif IPL '
      'boleh dikosongkan (memakai tarif perumahan).'],
  ['3. Sheet "Warga" (opsional): rumah harus ada di master atau di sheet '
      'Rumah. Email wajib di mode online (untuk akun login warga).'],
  ['4. Data yang sudah ada tidak digandakan; file aman diunggah ulang.'],
  ['5. Agar nol di depan tidak hilang, format kolom No. Rumah sebagai Teks.'],
];

/// Template kosong dengan contoh isian.
Uint8List buildTemplate() => _workbook({
      sheetRumah: (
        _rumahHeader,
        [
          ['Cluster Anggrek', 'Tipe 36/72', 36, 72, null, 'A1', '01-20'],
          ['Cluster Anggrek', 'Tipe 45/90', 45, 90, null, 'A2', '01-15, 16A'],
          ['Cluster Melati', 'Tipe 60/120', 60, 120, 350000, 'M1', '1-10'],
        ],
      ),
      sheetWarga: (
        _wargaHeader,
        [
          ['Budi Santoso', 'Cluster Anggrek', 'A1', '05', '0812-3456-7890',
              'budi@contoh.com'],
        ],
      ),
      sheetPetunjuk: (['Petunjuk'], _petunjuk),
    });

/// Data perumahan aktif dalam format template (untuk diedit & diunggah ulang).
Uint8List buildExport(EstateStore s) {
  final rumah = <List<Object?>>[];
  for (final c in s.sortedClusters) {
    for (final b in s.blocksOf(c.id)) {
      final t = s.houseTypeById(b.typeId);
      rumah.add([
        c.name,
        t?.name ?? '',
        t?.buildingArea,
        t?.landArea,
        t?.monthlyFee,
        b.name,
        compressHouseNumbers(s.housesOf(b.id).map((h) => h.number).toList()),
      ]);
    }
  }
  final warga = <List<Object?>>[];
  for (final r in s.residents) {
    final h = r.houseId == null ? null : s.houseById(r.houseId!);
    if (h == null) continue;
    warga.add([
      r.name,
      s.clusterById(h.clusterId)?.name ?? '',
      s.blockById(h.blockId)?.name ?? '',
      h.number,
      r.phone,
      r.email ?? '',
    ]);
  }
  return _workbook({
    sheetRumah: (_rumahHeader, rumah),
    sheetWarga: (_wargaHeader, warga),
    sheetPetunjuk: (['Petunjuk'], _petunjuk),
  });
}

/// Daftar akun warga hasil import (password sementara).
Uint8List buildAccountsSheet(List<ResidentAccount> accounts) => _workbook({
      'Akun Warga': (
        ['Nama', 'Rumah', 'Email', 'Password sementara', 'Status'],
        [
          for (final a in accounts)
            [
              a.name,
              a.house,
              a.email,
              a.password ?? '',
              a.error == null ? 'Berhasil' : 'Gagal: ${a.error}',
            ],
        ],
      ),
    });

/// ["01","02","03","05","12A"] -> "01-03, 05, 12A".
String compressHouseNumbers(List<String> numbers) {
  final parts = <String>[];
  var i = 0;
  while (i < numbers.length) {
    final start = numbers[i];
    final s = int.tryParse(start);
    var j = i;
    if (s != null) {
      while (j + 1 < numbers.length) {
        final next = numbers[j + 1];
        final n = int.tryParse(next);
        if (n == null || n != s + (j + 1 - i) || next.length != start.length) {
          break;
        }
        j++;
      }
    }
    parts.add(j - i >= 2 ? '$start-${numbers[j]}' : start);
    if (j - i == 1) parts.add(numbers[j]);
    i = j + 1;
  }
  return parts.join(', ');
}

// ---------------------------------------------------------------------------
// Membaca
// ---------------------------------------------------------------------------

String _cell(xl.Data? d) {
  final v = d?.value;
  final s = switch (v) {
    null => '',
    xl.IntCellValue(:final value) => '$value',
    xl.DoubleCellValue(:final value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value',
    xl.TextCellValue(:final value) => value.toString(),
    xl.FormulaCellValue() => '',
    _ => v.toString(),
  };
  return s.trim();
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Posisi kolom menurut judul (tidak peka urutan & huruf besar/kecil).
Map<String, int> _columns(List<String> header) {
  final cols = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final h = _norm(header[i]);
    if (h.isEmpty) continue;
    String? key;
    if (h.contains('cluster')) {
      key = 'cluster';
    } else if (h.contains('tarif') || h.contains('ipl')) {
      key = 'fee';
    } else if (h.contains('bangunan') || h == 'lb') {
      key = 'lb';
    } else if (h.contains('tanah') || h == 'lt') {
      key = 'lt';
    } else if (h.startsWith('tipe') || h.startsWith('type')) {
      key = 'tipe';
    } else if (h.contains('blok') || h.contains('block')) {
      key = 'blok';
    } else if (h.contains('rumah') || h.contains('nomor')) {
      key = 'no';
    } else if (h.contains('nama')) {
      key = 'nama';
    } else if (h.contains('hp') || h.contains('telp') || h.contains('telepon') ||
        h.contains('whatsapp') || h == 'wa') {
      key = 'hp';
    } else if (h.contains('email') || h.contains('e mail')) {
      key = 'email';
    }
    if (key != null) cols.putIfAbsent(key, () => i);
  }
  return cols;
}

/// Baris data sebuah sheet: (nomor baris Excel, nilai per kolom).
({Map<String, int> cols, List<(int, List<String>)> rows})? _readSheet(
    xl.Excel book, String wanted, List<String> requiredCols) {
  xl.Sheet? sheet;
  for (final e in book.tables.entries) {
    if (_norm(e.key).contains(wanted)) {
      sheet = e.value;
      break;
    }
  }
  if (sheet == null) return null;
  final all = sheet.rows;
  for (var h = 0; h < all.length && h < 10; h++) {
    final cols = _columns(all[h].map(_cell).toList());
    if (requiredCols.every(cols.containsKey)) {
      final rows = <(int, List<String>)>[];
      for (var r = h + 1; r < all.length; r++) {
        final values = all[r].map(_cell).toList();
        if (values.every((v) => v.isEmpty)) continue;
        rows.add((r + 1, values));
      }
      return (cols: cols, rows: rows);
    }
  }
  return (cols: <String, int>{}, rows: <(int, List<String>)>[]);
}

int? _intOrNull(String s) =>
    s.isEmpty ? null : int.tryParse(s.replaceAll(RegExp(r'[.,\s]'), ''));

/// Membaca workbook dan menyusun rencana import terhadap data perumahan
/// aktif di [s]. [requireEmail]: email warga wajib (mode Firebase).
ImportPlan parseWorkbook(List<int> bytes, EstateStore s,
    {bool requireEmail = false}) {
  final plan = ImportPlan();
  final xl.Excel book;
  try {
    book = xl.Excel.decodeBytes(bytes);
  } catch (_) {
    plan.errors.add('File tidak bisa dibaca. Gunakan format .xlsx '
        '(Excel 2007 ke atas / Google Sheets → Unduh → .xlsx).');
    return plan;
  }

  // ----- indeks data yang sudah ada -----
  final clusterByName = {for (final c in s.clusters) normName(c.name): c};
  Cluster? existingCluster(String name) => clusterByName[normName(name)];
  HouseType? existingType(String cluster, String type) {
    final c = existingCluster(cluster);
    if (c == null) return null;
    for (final t in s.typesOf(c.id)) {
      if (normName(t.name) == normName(type)) return t;
    }
    return null;
  }

  HouseBlock? existingBlock(String cluster, String block) {
    final c = existingCluster(cluster);
    if (c == null) return null;
    for (final b in s.blocksOf(c.id)) {
      if (normName(b.name) == normName(block)) return b;
    }
    return null;
  }

  House? existingHouse(String cluster, String block, String number) {
    final b = existingBlock(cluster, block);
    if (b == null) return null;
    for (final h in s.housesOf(b.id)) {
      if (normNumber(h.number) == normNumber(number)) return h;
    }
    return null;
  }

  // ----- sheet Rumah -----
  final rumah = _readSheet(book, 'rumah', const ['cluster', 'tipe', 'blok', 'no']);
  final planClusters = <String>{};
  final planTypes = <String, PlanType>{};
  final planBlocks = <String, PlanBlock>{};
  final planHouses = <String>{};

  if (rumah == null) {
    plan.warnings.add('Sheet "Rumah" tidak ditemukan; hanya data warga yang diproses.');
  } else if (rumah.cols.isEmpty) {
    plan.errors.add('Sheet "Rumah": judul kolom tidak dikenali. Gunakan '
        'template (Cluster, Tipe, Luas Bangunan, Luas Tanah, Blok, No. Rumah).');
  } else {
    String get(List<String> row, String key) {
      final i = rumah.cols[key];
      return i == null || i >= row.length ? '' : row[i];
    }

    for (final (line, row) in rumah.rows) {
      final where = 'Rumah baris $line';
      final cluster = get(row, 'cluster');
      final type = get(row, 'tipe');
      final block = get(row, 'blok');
      final numbers = get(row, 'no');
      final lbText = get(row, 'lb'), ltText = get(row, 'lt');
      final feeText = get(row, 'fee');
      final missing = [
        if (cluster.isEmpty) 'Cluster',
        if (type.isEmpty) 'Tipe',
        if (block.isEmpty) 'Blok',
        if (numbers.isEmpty) 'No. Rumah',
      ];
      if (missing.isNotEmpty) {
        plan.errors.add('$where: ${missing.join(', ')} kosong.');
        continue;
      }
      if (cluster.length > 60 || type.length > 40 || block.length > 20) {
        plan.errors.add('$where: nama cluster/tipe/blok terlalu panjang.');
        continue;
      }
      final lb = _intOrNull(lbText), lt = _intOrNull(ltText);
      final typeFee = _intOrNull(feeText.replaceAll(RegExp(r'^rp\s*', caseSensitive: false), ''));
      if (feeText.isNotEmpty && (typeFee == null || typeFee <= 0)) {
        plan.errors.add('$where: Tarif IPL harus angka.');
        continue;
      }
      if ((lbText.isNotEmpty && (lb == null || lb <= 0)) ||
          (ltText.isNotEmpty && (lt == null || lt <= 0))) {
        plan.errors.add('$where: luas bangunan/tanah harus angka.');
        continue;
      }
      final List<String> expanded;
      try {
        expanded = expandHouseNumbers(numbers);
      } on FormatException catch (e) {
        plan.errors.add('$where: No. Rumah ${e.message}.');
        continue;
      }

      // Cluster
      final ck = normName(cluster);
      if (existingCluster(cluster) == null && planClusters.add(ck)) {
        plan.clusters.add(cluster);
      }

      // Tipe (milik cluster)
      final tk = '$ck|${normName(type)}';
      final exType = existingType(cluster, type);
      if (exType != null) {
        if ((lb != null && lb != exType.buildingArea) ||
            (lt != null && lt != exType.landArea)) {
          plan.warnings.add('$where: luas ${exType.name} berbeda dengan data '
              'yang ada; data yang ada dipertahankan.');
        }
        if (typeFee != null && typeFee != exType.monthlyFee) {
          plan.warnings.add('$where: tarif IPL ${exType.name} berbeda dengan '
              'data yang ada; ubah lewat Master Data bila perlu.');
        }
      } else if (planTypes[tk] case final pt?) {
        if ((lb != null && lb != pt.buildingArea) ||
            (lt != null && lt != pt.landArea)) {
          plan.warnings.add('$where: luas $type berbeda dengan baris '
              'sebelumnya; dipakai yang pertama.');
        }
      } else {
        final t = PlanType(cluster, type, lb, lt, monthlyFee: typeFee);
        planTypes[tk] = t;
        plan.types.add(t);
      }

      // Blok (satu tipe)
      final bk = '$ck|${normName(block)}';
      final exBlock = existingBlock(cluster, block);
      if (exBlock != null) {
        final exBlockType = s.houseTypeById(exBlock.typeId);
        if (exBlockType != null && normName(exBlockType.name) != normName(type)) {
          plan.errors.add('$where: Blok $block di $cluster sudah bertipe '
              '${exBlockType.name}, bukan $type.');
          continue;
        }
      } else if (planBlocks[bk] case final pb?) {
        if (normName(pb.type) != normName(type)) {
          plan.errors.add('$where: Blok $block di $cluster ditulis dengan dua '
              'tipe berbeda (${pb.type} dan $type).');
          continue;
        }
      } else {
        final b = PlanBlock(cluster, type, block);
        planBlocks[bk] = b;
        plan.blocks.add(b);
      }

      // No. rumah
      for (final n in expanded) {
        final hk = '$bk|${normNumber(n)}';
        if (existingHouse(cluster, block, n) != null) {
          if (planHouses.add(hk)) plan.existingHouses++;
          continue;
        }
        if (planHouses.add(hk)) plan.houses.add(PlanHouse(cluster, block, n));
      }
    }
  }

  // ----- sheet Warga (opsional) -----
  final warga =
      _readSheet(book, 'warga', const ['nama', 'cluster', 'blok', 'no']);
  if (warga != null && warga.cols.isEmpty && warga.rows.isEmpty) {
    plan.errors.add('Sheet "Warga": judul kolom tidak dikenali. Gunakan '
        'template (Nama, Cluster, Blok, No. Rumah, No. HP, Email).');
  } else if (warga != null) {
    String get(List<String> row, String key) {
      final i = warga.cols[key];
      return i == null || i >= row.length ? '' : row[i];
    }

    final usedHouses = <String>{};
    final usedEmails = <String>{
      for (final r in s.residents)
        if ((r.email ?? '').isNotEmpty) r.email!.toLowerCase(),
    };
    for (final (line, row) in warga.rows) {
      final where = 'Warga baris $line';
      final name = get(row, 'nama');
      final cluster = get(row, 'cluster');
      final block = get(row, 'blok');
      final number = get(row, 'no');
      final phone = get(row, 'hp');
      final email = get(row, 'email').toLowerCase();
      final missing = [
        if (name.isEmpty) 'Nama',
        if (cluster.isEmpty) 'Cluster',
        if (block.isEmpty) 'Blok',
        if (number.isEmpty) 'No. Rumah',
        if (phone.isEmpty) 'No. HP',
        if (requireEmail && email.isEmpty) 'Email',
      ];
      if (missing.isNotEmpty) {
        plan.errors.add('$where: ${missing.join(', ')} kosong.');
        continue;
      }
      if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        plan.errors.add('$where: email "$email" tidak valid.');
        continue;
      }
      final hk =
          '${normName(cluster)}|${normName(block)}|${normNumber(number)}';
      final exHouse = existingHouse(cluster, block, number);
      if (exHouse == null && !planHouses.contains(hk)) {
        plan.errors.add('$where: rumah $cluster $block/$number tidak ada di '
            'master data maupun sheet Rumah.');
        continue;
      }
      if (!usedHouses.add(hk)) {
        plan.errors.add('$where: rumah $block/$number dipakai dua kali di file.');
        continue;
      }
      if (exHouse != null) {
        final occupant = s.residentOfHouse(exHouse.id);
        if (occupant != null) {
          if (normName(occupant.name) == normName(name)) {
            plan.existingResidents++;
          } else {
            plan.errors.add('$where: rumah $block/$number sudah ditempati '
                '${occupant.name}.');
          }
          continue;
        }
      }
      if (email.isNotEmpty && !usedEmails.add(email)) {
        plan.errors.add('$where: email $email sudah dipakai warga lain.');
        continue;
      }
      plan.residents.add(PlanResident(
        name: name,
        cluster: cluster,
        block: block,
        number: number,
        phone: phone,
        email: email,
      ));
    }
  }

  if (rumah == null && warga == null) {
    plan.errors.add('Tidak ada sheet "Rumah" atau "Warga" di file ini. '
        'Gunakan template dari aplikasi.');
  }
  return plan;
}
