/// Daftar suara adzan yang bisa dipilih warga.
///
/// Menambah suara (file dari pengelola aplikasi):
/// 1. Android: salin file ke `android/app/src/main/res/raw/` dengan nama
///    huruf kecil + garis bawah, mis. `adzan_makkah.mp3`.
/// 2. iOS: konversi ke `.caf` (maks. 30 detik, batas iOS), mis.
///    `adzan_makkah.caf`, lalu tambahkan ke target Runner di Xcode.
/// 3. Daftarkan di [adzanSounds] di bawah, mis.
///    `AdzanSound('makkah', 'Adzan Makkah', androidRaw: 'adzan_makkah',
///     iosFile: 'adzan_makkah.caf')`.
class AdzanSound {
  const AdzanSound(this.id, this.label, {this.androidRaw, this.iosFile});

  final String id;
  final String label;

  /// Nama file di res/raw tanpa ekstensi (null = bunyi notifikasi bawaan).
  final String? androidRaw;

  /// Nama file suara di bundle iOS (null = bunyi bawaan).
  final String? iosFile;

  bool get isDefault => androidRaw == null && iosFile == null;
}

const defaultAdzanSound = AdzanSound('default', 'Bunyi notifikasi bawaan');

/// Suara yang tersedia. File adzan ditambahkan di sini setelah dikirim.
const adzanSounds = <AdzanSound>[
  defaultAdzanSound,
];

AdzanSound adzanSoundById(String? id) =>
    adzanSounds.where((s) => s.id == id).firstOrNull ?? defaultAdzanSound;
