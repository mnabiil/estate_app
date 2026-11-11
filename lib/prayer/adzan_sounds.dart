/// Daftar suara adzan yang bisa dipilih warga.
///
/// Menambah suara:
/// 1. Android: MP3 di `android/app/src/main/res/raw/adzan_<nama>.mp3`
///    (huruf kecil + garis bawah; durasi penuh).
/// 2. iOS: potongan ≤ 30 detik (batas iOS) format CAF di
///    `assets/adzan/adzan_<nama>.caf` — otomatis disalin ke Library/Sounds.
///    Contoh konversi:
///    `ffmpeg -i in.mp3 -t 29.5 -af afade=t=out:st=27.5:d=2 -ac 1 -ar 22050
///     -c:a adpcm_ima_qt -f caf adzan_<nama>.caf`
/// 3. Daftarkan di [adzanSounds] di bawah.
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

/// Suara adzan bawaan untuk pengguna baru.
const initialAdzanSoundId = 'makkah';

/// Suara yang tersedia.
const adzanSounds = <AdzanSound>[
  AdzanSound('makkah', 'Adzan Makkah',
      androidRaw: 'adzan_makkah', iosFile: 'adzan_makkah.caf'),
  AdzanSound('madinah', 'Adzan Madinah',
      androidRaw: 'adzan_madinah', iosFile: 'adzan_madinah.caf'),
  AdzanSound('misyari', 'Adzan Misyari Rasyid',
      androidRaw: 'adzan_misyari', iosFile: 'adzan_misyari.caf'),
  defaultAdzanSound,
];

AdzanSound adzanSoundById(String? id) =>
    adzanSounds.where((s) => s.id == id).firstOrNull ?? defaultAdzanSound;
