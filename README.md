# Amani Living — Aplikasi Manajemen Perumahan (Prototipe)

<p align="center"><img src="assets/branding/logo_stacked.png" width="220" alt="Logo Amani Living"></p>

Aplikasi Flutter untuk Android & iOS yang mengelola perumahan/cluster.
Dua peran: **Warga** dan **Pengelola**. Data masih contoh (in-memory), belum ada backend.

## Fitur

| Fitur | Warga | Pengelola |
|---|---|---|
| Beranda (ringkasan) | Tagihan, keluhan, tamu hari ini | Jumlah warga, tunggakan, keluhan aktif, tamu |
| Tagihan IPL | Pilih satu/beberapa tagihan → transfer ke rekening perumahan dengan kode unik → unggah bukti | Atur rekening, verifikasi/tolak bukti transfer, buat tagihan bulan ini |
| Keluhan | Buat (dengan foto, maks. 3) & pantau status | Lihat semua, ubah status (Baru/Diproses/Selesai) |
| Tamu | Daftarkan tamu → dapat kode akses 6 digit | Log tamu, check-in |
| Pengumuman | Baca | Buat pengumuman |
| Ijin renovasi | Ajukan (kecil/besar, detail, jangka waktu, lampiran file); setelah disetujui bayar deposit + bukti; catat barang masuk/keluar dengan foto | Tinjau & setujui/tolak, verifikasi deposit (atau terima tunai), perpanjang, tandai selesai, kembalikan deposit (bisa dipotong), catat barang dengan foto |
| Data warga | — | Cari, tambah (pilih rumah dari daftar), lihat riwayat IPL |
| Akun | Daftar sendiri (menunggu verifikasi), ganti password; kepala keluarga menambah akun anggota rumah (keluarga/penyewa) | Verifikasi pendaftaran warga (setujui/tolak), kelola anggota rumah setiap warga, ganti password |
| Master data | — | Perumahan (bisa lebih dari satu) → Cluster → Tipe rumah (LB/LT) → Blok → No. rumah (tambah nomor sekaligus per rentang); **import/ekspor Excel** |

## Tampilan

Gaya visual terinspirasi UI kit *Rise Real Estate* (Figma Community): teks navy, warna utama
teal, aksen hijau lime, kartu abu muda bersudut besar. Font **Lato** & **Raleway** dibundel di
`assets/fonts/` (SIL Open Font License). Semua warna dan gaya komponen diatur di `lib/theme.dart`.

## Logo & nama

**Amani** berarti *damai* (Swahili) dan dekat dengan *amān*, *aman/tenteram* (Arab);
**Living** menegaskan kehidupan sehari-hari warga yang damai dan aman. Logo: atap yang menaungi (rumah sebagai tempat berlindung) dan dua daun
yang tumbuh berdampingan dari dalam rumah (kehidupan yang tumbuh, lingkungan hijau, dan warga
yang hidup bertetangga). Warna: teal `#234F68`, lime `#8BC83F`, navy `#252B5C`.

File di `assets/branding/`: `icon.svg` / `icon_1024.png` (ikon aplikasi), `logo_mark.svg`
(simbol), `logo_horizontal*.png` & `logo_stacked.png` (logo lengkap).

## Akun warga

**Dibuat pengelola** (tab Warga → +, atau import Excel): server membuat akun dengan password
sementara; warga **wajib membuat password baru** saat login pertama.

**Registrasi mandiri** (layar login → *Daftar sebagai warga*):
pilih Perumahan → Cluster → Tipe → Blok → No. rumah (hanya rumah kosong & tidak sedang
diajukan), isi data diri (+ foto KTP/bukti hunian opsional) dan email/password →
akun berstatus **pendaftar** (belum bisa membaca data perumahan) → pengelola
**menyetujui** (akun menjadi warga, aplikasi terbuka otomatis) atau **menolak** dengan alasan
(pendaftar bisa memperbaiki & mengajukan ulang). Pendaftaran bisa ditutup per perumahan di
profil perumahan. Cloud Functions: `listRegistrationEstates`, `getRegistrationOptions`
(tanpa login), `submitRegistration`, `approveRegistration`.

Semua pengguna bisa **ganti password** di menu Akun.

**Anggota rumah**: kepala keluarga (atau pengelola) menambah akun untuk pasangan, anak, orang
tua, saudara, atau penyewa (maks. 6) lewat Akun → *Anggota rumah*. Anggota login dengan akunnya
sendiri (password sementara, wajib diganti) dan berbagi data rumah yang sama karena memakai
`residentId` yang sama; hanya kepala keluarga & pengelola yang bisa menambah/menghapus anggota.
Cloud Functions: `addHouseholdMember`, `removeHouseholdMember` (menghapus akun login juga).

**Gabung ke rumah** (registrasi mandiri): rumah yang sudah berpenghuni juga bisa dipilih saat
mendaftar. Pendaftaran menjadi *permintaan gabung* dengan hubungan (suami/istri, anak, orang
tua, saudara, penyewa, lainnya) dan disetujui oleh **kepala keluarga rumah itu** (Akun →
Anggota rumah) atau pengelola. Setelah disetujui, pendaftar menjadi anggota rumah. Nama
penghuni tidak ditampilkan ke pendaftar.

## Tim pengelola & level akses

Akun → **Tim pengelola** (hanya **pemilik**). Tab *Level akses* berisi level yang bisa dibuat
sendiri (template: Bendahara, Admin Warga, Satpam, Koordinator Bangunan) dengan hak:
master data, warga & pendaftaran, tagihan & pembayaran, rekening pembayaran, keluhan, tamu, pengumuman, ijin
renovasi, catat barang renovasi. Tab *Tim* untuk menambah pengelola (email; akun baru dibuat
dengan password sementara oleh `addStaff`), mengganti level, atau mengeluarkan (`removeStaff`).
Pemilik punya semua hak; minimal harus ada satu pemilik.
**Akses perumahan**: anggota tim bisa diberi akses ke beberapa perumahan atau **semua
perumahan** (termasuk yang dibuat nanti; `setStaffEstates`, `createEstate` ikut menyalin).
Level akses disalin ke tiap perumahan. Pengelola memilih perumahan aktif di **Akun**. Hak dicek di aplikasi,
`firestore.rules` (`can(estateId, perm)`) dan Cloud Functions. Pengelola lama yang belum tercatat
di `staff` dianggap pemilik.

## Foto profil

Akun → ketuk avatar → **Ganti foto profil** (kamera/galeri, dengan pratinjau & konfirmasi) atau
hapus. Foto per akun (kepala keluarga & anggota rumah masing-masing), tampil di Akun & Beranda.
Disimpan di Storage `users/{uid}/` dan `users/{uid}.photoUrl`.

## Pengumuman

Pengelola (hak pengumuman) membuat pengumuman dengan **foto sampul**, **tanggal berakhir**
(opsional) dan pilihan **perumahan tujuan**. Daftar tampil seperti portal berita; ketuk untuk
membaca versi artikel. Warga hanya melihat pengumuman yang masih berlaku; pengelola melihat
semua dan bisa **menghapus**. Foto: `estates/{estateId}/announcements/`.

## Satu akun, beberapa rumah

Satu akun warga bisa punya beberapa unit di satu atau beberapa perumahan. Pengelola cukup
menambah warga (atau anggota rumah) dengan **email yang sudah punya akun warga**: rumah baru
ditambahkan ke akun itu, tanpa akun/password baru. Warga memilih **rumah aktif** di Akun;
tagihan, keluhan, tamu, renovasi & pembayaran mengikuti rumah aktif. Peran bisa berbeda per
rumah (kepala keluarga di rumah A, anggota/penyewa di rumah B).

Profil: rumah utama tetap `estateId`/`residentId`; rumah lain di `homeKeys`
(`"estateId/residentId"`), `homeEstates`, `memberKeys` (rumah sebagai anggota), `homeLabels`,
`homeRelations`. Akun lama tidak perlu dimigrasi.

## Pembayaran IPL (transfer + kode unik)

Pembayaran **hanya transfer** ke rekening perumahan (Tagihan → ikon bank, hak *rekening
pembayaran* — terpisah dari hak *tagihan*;
maks. 5 rekening per perumahan).

1. Warga menekan **Bayar** dan memilih tagihan. **Beberapa tagihan bisa dibayar sekaligus**
   dalam satu transfer, tetapi tagihan **terlama wajib ikut** (mencentang bulan yang lebih baru
   otomatis mencentang bulan sebelumnya).
2. Server (`createPayment`) membuat **kode unik 3 digit** (001–999, tidak dipakai rumah lain yang
   sedang membayar) → total transfer = tagihan + kode, mis. Rp 750.000 + 457 = **Rp 750.457**,
   berita transfer `IPL-A105-457`. Berlaku 24 jam; satu rumah hanya satu pembayaran aktif.
3. Warga transfer, lalu **unggah foto bukti**. Status: *menunggu verifikasi*; pengelola dengan hak
   tagihan mendapat notifikasi.
4. Pengelola mencocokkan mutasi rekening → **Terima** (`verifyPayment`: semua tagihan lunas) atau
   **Tolak** dengan alasan (warga unggah ulang atau membatalkan).

Kode yang kedaluwarsa/dibatalkan tidak mengunci tagihan; warga cukup membuat kode baru.

## Tarif IPL & jatuh tempo

Master Data → profil perumahan: **tarif IPL** perumahan dan **tanggal jatuh tempo** (1–28,
default 10). Tarif bisa dibedakan **per tipe rumah** (form tipe rumah, opsional; kosong =
tarif perumahan). Tagihan menyimpan nominal & tanggal jatuh temponya saat dibuat, jadi
perubahan pengaturan hanya berlaku untuk tagihan berikutnya. Pengingat dikirim **H-2** dan
pemberitahuan terlambat **H+2** dari tanggal jatuh tempo.

## Notifikasi push

Firebase Cloud Messaging, dikirim server (Cloud Functions) ke perangkat warga & anggota rumah:

| Kejadian | Function | Isi |
|---|---|---|
| Pengumuman baru | `notifyAnnouncement` | Judul + cuplikan isi |
| Tagihan terbit | `notifyBillCreated` | "Tagihan IPL November 2026 – Rp 250.000" |
| H-2 jatuh tempo, 09.00 WIB | `remindBills` (harian) | Pengingat untuk yang belum bayar |
| H+2 jatuh tempo, 09.00 WIB | `remindBills` (harian) | Tagihan lewat jatuh tempo |
| Bukti transfer diunggah | `notifyPayment` | Ke pengelola berhak tagihan: "Mohon verifikasi" |
| Pembayaran diterima / ditolak | `notifyPayment` | Ke warga: lunas, atau alasan penolakan |

- Token perangkat: `users/{uid}/devices/{token}` (hanya pemilik); dihapus saat logout & bila
  sudah tidak valid. Pengiriman per pengguna, bukan topik publik.
- Preferensi: Akun → **Notifikasi** (`users/{uid}.notifPrefs`).
- Aplikasi terbuka: tampil sebagai banner; notifikasi diketuk membuka tab Tagihan /
  halaman Pengumuman.

**Setup iOS** (sekali): Firebase Console → Project settings → Cloud Messaging → unggah
APNs Auth Key; di Xcode tambahkan capability *Push Notifications* dan *Background Modes →
Remote notifications* (Info.plist sudah berisi `UIBackgroundModes`). Android tidak perlu
langkah tambahan (izin `POST_NOTIFICATIONS` sudah ada di manifest).

## Import dari Excel

Master Data → **Import dari Excel** (pengelola):

1. **Unduh template** (atau *Unduh data saat ini* untuk mengedit data yang ada).
2. Isi sheet **Rumah** — `Cluster | Tipe | Luas Bangunan | Luas Tanah | Blok | No. Rumah`;
   satu baris per blok, No. Rumah boleh rentang `01-20`, daftar `1, 2, 5`, atau `12A`.
   Sheet **Warga** (opsional) — `Nama | Cluster | Blok | No. Rumah | No. HP | Email`.
3. Unggah file `.xlsx` → **pratinjau** jumlah data baru, data yang sudah ada (dilewati),
   serta error/peringatan per baris → **Import sekarang**.
4. Mode Firebase: akun warga dibuat lewat `createResident`; daftar password sementara
   bisa diunduh sebagai Excel.

Data diimpor ke perumahan yang sedang aktif dan aman diunggah ulang (tidak digandakan).

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
6. Login di aplikasi sebagai pengelola → **Akun → Master data**, isi berurutan:
   Perumahan → Cluster → Tipe rumah → Blok (pilih tipenya) → No. rumah.
   Perumahan tambahan bisa dibuat dari layar yang sama (Cloud Function `createEstate`
   menambahkannya ke `estateIds` pengelola).
7. Tab **Warga** → tambah warga, pilih rumahnya dari daftar (akun & password
   sementara warga dibuat otomatis oleh Cloud Function `createResident`).

### Struktur data Firestore

```
users/{uid}                      { estateId, estateIds?, role: warga|pengelola|pendaftar, residentId?, name,
                                   mustChangePassword?, householdRole?: anggota, relation? }
estates/{estateId}               { name, address, monthlyFee, billDueDay (1–28), renovationDepositSmall,
                                   renovationDepositLarge, registrationOpen,
                                   bankAccounts[{title?, bankName, accountNumber, accountName}] }
  staff/{uid}                    { name, email, phone, isOwner, roleId, roleName, permissions[],
                                   allEstates, estateIds[] }
  adminRoles/{id}                { name, permissions[] }
  members/{uid}                  { residentId, name, relation, phone, email, addedBy, createdAt }
  registrations/{uid}            { estateId, name, phone, email, houseId, houseNo, clusterName, occupancy,
                                   docUrl, kind: baru|gabung, relation?, residentId?,
                                   status: menunggu|disetujui|ditolak, note, createdAt, reviewedAt }
  clusters/{id}                  { name }
  blocks/{id}                    { clusterId, typeId, name }
  houseTypes/{id}                { clusterId, name, buildingArea, landArea, monthlyFee? }
  houses/{id}                    { clusterId, blockId, number }
  residents/{residentId}         { name, houseId, houseNo, phone, email, uid }
  bills/{residentId_YYYY-MM}     { residentId, period, amount, dueDate ("YYYY-MM-DD"), status, paidAt, method,
                                   paymentId? }
  payments/{id}                  { residentId, billIds[], periods[], baseAmount, uniqueCode, reference,
                                   houseNo, residentName, status: menungguTransfer|menungguVerifikasi|
                                   ditolak|diterima|dibatalkan, createdAt, expiresAt, proofUrl,
                                   submittedAt, note, reviewedAt, reviewedBy }
  complaints/{id}                { residentId, title, description, category, status, photoUrls, createdAt }
  visitors/{id}                  { residentId, name, purpose, visitDate, code, checkedInAt }
  announcements/{id}             { title, body, photoUrl?, until? ("YYYY-MM-DD"), createdBy, createdAt }
  renovations/{id}               { residentId, type: kecil|besar, description, contractor, contractorPhone,
                                   startDate, endDate ("YYYY-MM-DD"), deposit, attachments[{name,url,size}],
                                   status, depositStatus, depositMethod, depositProofUrl,
                                   depositSubmittedAt, depositPaidAt, depositRefund, depositRefundedAt,
                                   adminNote, createdAt }
  renovationLogs/{id}            { renovationId, residentId, direction: masuk|keluar, item, quantity,
                                   note, photoUrls, at, recordedBy }
```

Foto keluhan di Firebase Storage: `estates/{estateId}/complaints/{residentId}/{complaintId}/{0-2}.jpg`.
Bukti transfer: `estates/{estateId}/payments/{residentId}/{paymentId}/`.
File renovasi: `estates/{estateId}/renovations/{residentId}/{renovationId}/` → `lampiran/`, `deposit/`, `barang/{logId}/`.

Alur ijin renovasi: **ajukan** (detail + jangka waktu + lampiran) → **disetujui** pengelola →
warga **bayar deposit** + bukti → pengelola **verifikasi** → pekerjaan berjalan (catat barang
masuk/keluar + foto) → **selesai** → **deposit dikembalikan**.

### Keamanan

- `firestore.rules`: warga hanya bisa membaca datanya sendiri; profil & peran tidak bisa diubah dari aplikasi.
- `storage.rules`: warga hanya bisa mengunggah foto keluhan ke foldernya sendiri (gambar, maks. 5 MB);
  foto hanya bisa dilihat pemiliknya & pengelola.
- Status **lunas** hanya diubah server saat pengelola memverifikasi transfer (`verifyPayment`);
  tagihan tidak bisa diubah langsung dari aplikasi.
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
- Opsional: pencocokan mutasi rekening otomatis (API bank / Moota) untuk verifikasi
- Scan QR kode tamu oleh satpam
