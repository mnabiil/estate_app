# Griya Kita — Aplikasi Manajemen Perumahan (Prototipe)

Aplikasi Flutter untuk Android & iOS yang mengelola perumahan/cluster.
Dua peran: **Warga** dan **Pengelola**. Data masih contoh (in-memory), belum ada backend.

## Fitur

| Fitur | Warga | Pengelola |
|---|---|---|
| Beranda (ringkasan) | Tagihan, keluhan, tamu hari ini | Jumlah warga, tunggakan, keluhan aktif, tamu |
| Tagihan IPL | Lihat & bayar (simulasi VA/QRIS/e-wallet) | Lihat semua, tandai lunas (tunai), buat tagihan bulan ini |
| Keluhan | Buat (dengan foto, maks. 3) & pantau status | Lihat semua, ubah status (Baru/Diproses/Selesai) |
| Tamu | Daftarkan tamu → dapat kode akses 6 digit | Log tamu, check-in |
| Pengumuman | Baca | Buat pengumuman |
| Data warga | — | Cari, tambah, lihat riwayat IPL |

## Tampilan

Gaya visual terinspirasi UI kit *Rise Real Estate* (Figma Community): teks navy, warna utama
teal, aksen hijau lime, kartu abu muda bersudut besar. Font **Lato** & **Raleway** dibundel di
`assets/fonts/` (SIL Open Font License). Semua warna dan gaya komponen diatur di `lib/theme.dart`.

## Menjalankan

1. Install Flutter SDK (3.27 atau lebih baru): https://docs.flutter.dev/get-started/install
2. Di folder ini, buat folder platform Android & iOS (file yang sudah ada tidak ditimpa):
   ```bash
   flutter create --project-name estate_app --platforms android,ios .
   ```
3. Ambil dependensi dan jalankan:
   ```bash
   flutter pub get
   flutter run
   ```
4. Uji: `flutter test`

> Build iOS butuh macOS + Xcode. Di Windows, uji di emulator/HP Android.

## Mode demo vs mode Firebase

Aplikasi otomatis memilih mode:

- **Demo**: bila `lib/firebase_options.dart` masih file sementara. Data contoh, login tanpa password.
- **Firebase**: setelah `flutterfire configure` dijalankan. Login email + password, data realtime di Firestore.

## Setup Firebase

1. Buat proyek di https://console.firebase.google.com (akun Google Anda).
   - **Authentication** → Sign-in method → aktifkan **Email/Password**.
   - **Firestore Database** → Create database → lokasi **asia-southeast2 (Jakarta)** → mode *production*.
   - Untuk Cloud Functions: upgrade ke paket **Blaze** (bayar sesuai pemakaian).
   - **Storage** → Get started (untuk foto keluhan).
2. Pasang alat CLI (butuh [Node.js LTS](https://nodejs.org)):
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   ```
3. Hubungkan aplikasi (menimpa `lib/firebase_options.dart`):
   ```bash
   flutterfire configure --platforms=android,ios
   ```
4. Deploy aturan keamanan & functions:
   ```bash
   cd functions && npm install && cd ..
   firebase deploy --only firestore:rules,storage,functions
   ```
5. **Buat pengelola pertama** (sekali saja, lewat Console):
   - Authentication → Add user → email & password pengelola. Salin **User UID**-nya.
   - Firestore → buat dokumen `estates/griya-asri`:
     `name` (string) = `Perumahan Griya Asri`, `monthlyFee` (number) = `250000`
   - Firestore → buat dokumen `users/<User UID>`:
     `estateId` = `griya-asri`, `role` = `pengelola`, `name` = `Pak Hendra`
6. Login di aplikasi sebagai pengelola → tab **Warga** → tambah warga (akun & password
   sementara warga dibuat otomatis oleh Cloud Function `createResident`).

### Struktur data Firestore

```
users/{uid}                      { estateId, role, residentId?, name }
estates/{estateId}               { name, monthlyFee }
  residents/{residentId}         { name, houseNo, phone, email, uid }
  bills/{residentId_YYYY-MM}     { residentId, period, amount, status, paidAt, method }
  complaints/{id}                { residentId, title, description, category, status, photoUrls, createdAt }
  visitors/{id}                  { residentId, name, purpose, visitDate, code, checkedInAt }
  announcements/{id}             { title, body, createdAt }
```

Foto keluhan di Firebase Storage: `estates/{estateId}/complaints/{residentId}/{complaintId}/{0-2}.jpg`.

### Keamanan

- `firestore.rules`: warga hanya bisa membaca datanya sendiri; profil & peran tidak bisa diubah dari aplikasi.
- `storage.rules`: warga hanya bisa mengunggah foto keluhan ke foldernya sendiri (gambar, maks. 5 MB);
  foto hanya bisa dilihat pemiliknya & pengelola.
- Status **lunas** dari warga hanya diubah server (`payBill`). Saat ini `payBill` masih
  **simulasi** (`functions/.env` → `PAYMENT_SIMULATION=true`). Matikan sebelum rilis dan ganti
  dengan payment gateway.
- Tagihan bulanan dibuat otomatis tiap tanggal 1 pukul 01.00 WIB (`generateMonthlyBills`).

## Struktur kode

```
lib/
  main.dart              # Entry point, inisialisasi Firebase (fallback ke demo)
  firebase_options.dart  # Dibuat oleh flutterfire configure
  models.dart            # Model + serialisasi Firestore
  store.dart             # State: mode demo & mode Firebase
  theme.dart             # Warna, font & gaya komponen (ubah tampilan di sini)
  utils.dart             # Format Rupiah & tanggal
  widgets.dart           # Komponen kecil + runAction (penanganan error)
  screens/               # Satu file per layar
functions/src/index.ts   # Cloud Functions
firestore.rules          # Aturan akses database
storage.rules            # Aturan akses foto (Storage)
```

## Langkah berikutnya

- Login OTP nomor HP (Firebase Phone Auth)
- Pembayaran nyata via payment gateway (Midtrans, Xendit)
- Notifikasi push (pengumuman, jatuh tempo IPL)
- Scan QR kode tamu oleh satpam
