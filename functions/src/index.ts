/**
 * Cloud Functions untuk Nilaya Living.
 *
 *  - createEstate        (callable)  pengelola membuat perumahan baru (multi-perumahan)
 *  - createResident      (callable)  pengelola menambah warga + membuat akun login
 *  - listRegistrationEstates / getRegistrationOptions (callable, tanpa login)
 *                                    daftar perumahan & rumah tersedia untuk pendaftaran
 *  - submitRegistration  (callable)  calon warga mengirim pendaftaran mandiri
 *  - approveRegistration (callable)  pengelola menyetujui pendaftaran -> akun jadi warga
 *  - payBill             (callable)  warga membayar tagihan (SIMULASI, lihat catatan)
 *  - generateMonthlyBills (terjadwal) membuat tagihan IPL tiap tanggal 1, 01.00 WIB
 *
 * Butuh paket Firebase "Blaze" untuk deploy.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { randomBytes } from "node:crypto";

initializeApp();
setGlobalOptions({ region: "asia-southeast2", maxInstances: 10 });

const db = getFirestore();
const DEFAULT_FEE = 250000;

type Profile = {
  estateId: string;
  /** Pengelola: semua perumahan yang dikelola (estateId = perumahan utama). */
  estateIds?: string[];
  role: "warga" | "pengelola" | "pendaftar";
  residentId?: string;
  name: string;
};

async function profileOf(uid: string | undefined): Promise<Profile> {
  if (!uid) throw new HttpsError("unauthenticated", "Silakan login terlebih dahulu.");
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Akun tidak terdaftar.");
  return snap.data() as Profile;
}

/** Pengelola perumahan ini? (estateId utama atau salah satu estateIds) */
function managesEstate(me: Profile, estateId: string): boolean {
  return (
    me.role === "pengelola" &&
    (me.estateId === estateId || (me.estateIds ?? []).includes(estateId))
  );
}

function requireText(value: unknown, field: string, max = 200): string {
  if (typeof value !== "string" || value.trim() === "" || value.length > max) {
    throw new HttpsError("invalid-argument", `${field} wajib diisi (maks ${max} karakter).`);
  }
  return value.trim();
}

/** "2026-11" menurut waktu Jakarta. */
function jakartaMonthKey(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(date);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}`;
}

// ---------------------------------------------------------------------------

export const createEstate = onCall(async (req) => {
  const uid = req.auth?.uid;
  const me = await profileOf(uid);
  if (me.role !== "pengelola") {
    throw new HttpsError("permission-denied", "Hanya pengelola yang bisa menambah perumahan.");
  }
  const data = req.data ?? {};
  const name = requireText(data.name, "Nama perumahan", 100);
  const address = typeof data.address === "string" ? data.address.trim().slice(0, 300) : "";
  const fee = Number(data.monthlyFee);
  if (!Number.isInteger(fee) || fee <= 0) {
    throw new HttpsError("invalid-argument", "Tarif IPL harus angka bulat > 0.");
  }
  const depositSmall = Number(data.renovationDepositSmall ?? 1000000);
  const depositLarge = Number(data.renovationDepositLarge ?? 5000000);
  for (const d of [depositSmall, depositLarge]) {
    if (!Number.isInteger(d) || d <= 0) {
      throw new HttpsError("invalid-argument", "Deposit renovasi harus angka bulat > 0.");
    }
  }
  const managed = Array.from(new Set([me.estateId, ...(me.estateIds ?? [])].filter(Boolean)));
  if (managed.length >= 20) {
    throw new HttpsError("resource-exhausted", "Maksimal 20 perumahan per akun.");
  }

  const estateRef = db.collection("estates").doc();
  const batch = db.batch();
  batch.set(estateRef, {
    name,
    address,
    monthlyFee: fee,
    renovationDepositSmall: depositSmall,
    renovationDepositLarge: depositLarge,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.update(db.doc(`users/${uid}`), {
    estateIds: FieldValue.arrayUnion(...managed, estateRef.id),
  });
  await batch.commit();
  return { estateId: estateRef.id };
});

// ---------------------------------------------------------------------------

export const createResident = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  if (!managesEstate(me, estateId)) {
    throw new HttpsError("permission-denied", "Hanya pengelola perumahan ini yang bisa menambah warga.");
  }
  const name = requireText(data.name, "Nama", 100);
  const houseId = requireText(data.houseId, "Rumah", 100);
  const phone = requireText(data.phone, "No. HP", 20);
  const email = requireText(data.email, "Email", 120).toLowerCase();

  // Rumah harus ada di master dan belum berpenghuni.
  const estateRef = db.doc(`estates/${estateId}`);
  const houseSnap = await estateRef.collection("houses").doc(houseId).get();
  if (!houseSnap.exists) {
    throw new HttpsError("not-found", "Rumah tidak ditemukan di master data.");
  }
  const house = houseSnap.data()!;
  const blockSnap = await estateRef.collection("blocks").doc(String(house.blockId)).get();
  const houseNo = `${blockSnap.get("name") ?? "?"}/${house.number}`;
  const occupied = await estateRef
    .collection("residents")
    .where("houseId", "==", houseId)
    .limit(1)
    .get();
  if (!occupied.empty) {
    throw new HttpsError("already-exists", `Rumah ${houseNo} sudah berpenghuni.`);
  }

  const tempPassword = randomBytes(9).toString("base64url");
  let uid: string;
  try {
    const user = await getAuth().createUser({ email, password: tempPassword, displayName: name });
    uid = user.uid;
  } catch (e: unknown) {
    const code = (e as { code?: string }).code;
    if (code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Email ini sudah dipakai akun lain.");
    }
    if (code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", "Format email tidak valid.");
    }
    throw e;
  }

  const residentRef = db.collection(`estates/${estateId}/residents`).doc();
  const batch = db.batch();
  batch.set(residentRef, {
    name,
    houseId,
    houseNo,
    phone,
    email,
    uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.doc(`users/${uid}`), {
    estateId,
    role: "warga",
    residentId: residentRef.id,
    name,
    // Password sementara: wajib diganti saat login pertama.
    mustChangePassword: true,
  });
  await batch.commit();

  return { residentId: residentRef.id, tempPassword };
});

// ---------------------------------------------------------------------------

/**
 * SIMULASI pembayaran: langsung menandai lunas.
 *
 * Hanya aktif bila PAYMENT_SIMULATION=true (lihat functions/.env).
 * Untuk produksi, ganti dengan: buat transaksi di Midtrans/Xendit -> kembalikan
 * URL/VA ke aplikasi -> tandai lunas di webhook setelah verifikasi signature.
 */
export const payBill = onCall(async (req) => {
  if (process.env.PAYMENT_SIMULATION !== "true") {
    throw new HttpsError("failed-precondition", "Pembayaran online belum diaktifkan.");
  }
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const billId = requireText(data.billId, "billId");
  const method = typeof data.method === "string" ? data.method.slice(0, 60) : "Simulasi";
  if (me.estateId !== estateId && !managesEstate(me, estateId)) {
    throw new HttpsError("permission-denied", "Akses ditolak.");
  }

  const ref = db.doc(`estates/${estateId}/bills/${billId}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Tagihan tidak ditemukan.");
    const bill = snap.data()!;
    if (me.role !== "pengelola" && bill.residentId !== me.residentId) {
      throw new HttpsError("permission-denied", "Ini bukan tagihan Anda.");
    }
    if (bill.status === "lunas") {
      throw new HttpsError("failed-precondition", "Tagihan ini sudah lunas.");
    }
    tx.update(ref, {
      status: "lunas",
      paidAt: FieldValue.serverTimestamp(),
      method: `${method} (simulasi)`,
    });
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------

export const generateMonthlyBills = onSchedule(
  { schedule: "0 1 1 * *", timeZone: "Asia/Jakarta" },
  async () => {
    const period = jakartaMonthKey(new Date());
    const estates = await db.collection("estates").get();

    for (const estate of estates.docs) {
      const fee = Number(estate.get("monthlyFee") ?? DEFAULT_FEE);
      const residents = await estate.ref.collection("residents").get();
      const writer = db.bulkWriter();
      for (const r of residents.docs) {
        // ID deterministik -> create() gagal bila tagihan bulan ini sudah ada (aman diulang).
        writer
          .create(estate.ref.collection("bills").doc(`${r.id}_${period}`), {
            residentId: r.id,
            period,
            amount: fee,
            status: "belumBayar",
            paidAt: null,
            method: null,
            createdAt: FieldValue.serverTimestamp(),
          })
          .catch(() => undefined);
      }
      await writer.close();
      console.log(`Tagihan ${period} untuk ${estate.id}: ${residents.size} warga diproses`);
    }
  },
);

// ---------------------------------------------------------------------------
// Registrasi mandiri warga
// ---------------------------------------------------------------------------

async function openEstate(estateId: string) {
  const snap = await db.doc(`estates/${estateId}`).get();
  if (!snap.exists || snap.get("registrationOpen") === false) {
    throw new HttpsError("failed-precondition", "Perumahan ini tidak menerima pendaftaran online.");
  }
  return snap;
}

/** ID rumah yang sudah ditempati warga atau sedang diajukan pendaftar lain. */
async function unavailableHouses(estateId: string, exceptUid?: string): Promise<Set<string>> {
  const estate = db.doc(`estates/${estateId}`);
  const [residents, pending] = await Promise.all([
    estate.collection("residents").select("houseId").get(),
    estate.collection("registrations").where("status", "==", "menunggu").get(),
  ]);
  const taken = new Set<string>();
  residents.docs.forEach((d) => {
    const h = d.get("houseId");
    if (typeof h === "string") taken.add(h);
  });
  pending.docs.forEach((d) => {
    if (d.id !== exceptUid) taken.add(String(d.get("houseId")));
  });
  return taken;
}

/** Tanpa login: perumahan yang membuka pendaftaran mandiri. */
export const listRegistrationEstates = onCall(async () => {
  const snap = await db.collection("estates").get();
  return {
    estates: snap.docs
      .filter((d) => d.get("registrationOpen") !== false)
      .map((d) => ({ id: d.id, name: d.get("name") ?? "", address: d.get("address") ?? "" }))
      .sort((a, b) => String(a.name).localeCompare(String(b.name))),
  };
});

/** Tanpa login: master data + ketersediaan rumah (tanpa data warga). */
export const getRegistrationOptions = onCall(async (req) => {
  const estateId = requireText(req.data?.estateId, "estateId");
  await openEstate(estateId);
  const estate = db.doc(`estates/${estateId}`);
  const [clusters, types, blocks, houses, taken] = await Promise.all([
    estate.collection("clusters").get(),
    estate.collection("houseTypes").get(),
    estate.collection("blocks").get(),
    estate.collection("houses").get(),
    unavailableHouses(estateId, req.auth?.uid),
  ]);
  const plain = (d: FirebaseFirestore.QueryDocumentSnapshot) => ({ id: d.id, ...d.data() });
  return {
    clusters: clusters.docs.map(plain),
    types: types.docs.map(plain),
    blocks: blocks.docs.map(plain),
    houses: houses.docs.map((d) => ({ ...plain(d), available: !taken.has(d.id) })),
  };
});

/**
 * Calon warga (sudah membuat akun email/password) mengirim pendaftaran.
 * Akun berperan "pendaftar" dan belum bisa membaca data perumahan sampai
 * disetujui pengelola. Bisa dipanggil ulang setelah ditolak.
 */
export const submitRegistration = onCall(async (req) => {
  const uid = req.auth?.uid;
  const email = req.auth?.token.email;
  if (!uid || !email) throw new HttpsError("unauthenticated", "Silakan buat akun terlebih dahulu.");
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "Perumahan");
  const houseId = requireText(data.houseId, "Rumah");
  const name = requireText(data.name, "Nama", 100);
  const phone = requireText(data.phone, "No. HP", 20);
  const occupancy = String(data.occupancy ?? "");
  if (!["pemilik", "penyewa", "keluarga"].includes(occupancy)) {
    throw new HttpsError("invalid-argument", "Status hunian tidak valid.");
  }
  const docUrl =
    typeof data.docUrl === "string" && data.docUrl.startsWith("https://") ? data.docUrl : null;

  const userRef = db.doc(`users/${uid}`);
  const existing = await userRef.get();
  if (existing.exists && existing.get("role") !== "pendaftar") {
    throw new HttpsError("already-exists", "Akun ini sudah terdaftar sebagai warga/pengelola.");
  }
  const prevEstate = existing.get("estateId");
  if (prevEstate && prevEstate !== estateId) {
    // Pindah pilihan perumahan: hapus pendaftaran lama.
    await db.doc(`estates/${prevEstate}/registrations/${uid}`).delete();
  }

  await openEstate(estateId);
  const estate = db.doc(`estates/${estateId}`);
  const house = await estate.collection("houses").doc(houseId).get();
  if (!house.exists) throw new HttpsError("not-found", "Rumah tidak ditemukan.");
  const taken = await unavailableHouses(estateId, uid);
  if (taken.has(houseId)) {
    throw new HttpsError("already-exists", "Rumah ini sudah berpenghuni atau sedang diajukan orang lain.");
  }
  const [block, cluster] = await Promise.all([
    estate.collection("blocks").doc(String(house.get("blockId"))).get(),
    estate.collection("clusters").doc(String(house.get("clusterId"))).get(),
  ]);

  const batch = db.batch();
  batch.set(estate.collection("registrations").doc(uid), {
    estateId,
    name,
    phone,
    email: email.toLowerCase(),
    houseId,
    houseNo: `${block.get("name") ?? "?"}/${house.get("number")}`,
    clusterName: cluster.get("name") ?? "",
    occupancy,
    docUrl,
    status: "menunggu",
    note: "",
    createdAt: FieldValue.serverTimestamp(),
    reviewedAt: null,
  });
  batch.set(userRef, { estateId, role: "pendaftar", name });
  await batch.commit();
  return { ok: true };
});

/** Pengelola menyetujui pendaftaran: buat data warga & jadikan akun warga. */
export const approveRegistration = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const uid = requireText(data.uid, "uid");
  if (!managesEstate(me, estateId)) {
    throw new HttpsError("permission-denied", "Hanya pengelola perumahan ini yang bisa menyetujui.");
  }
  const estate = db.doc(`estates/${estateId}`);
  const regRef = estate.collection("registrations").doc(uid);
  const residentRef = estate.collection("residents").doc();

  await db.runTransaction(async (tx) => {
    const reg = await tx.get(regRef);
    if (!reg.exists || reg.get("status") !== "menunggu") {
      throw new HttpsError("failed-precondition", "Pendaftaran tidak ditemukan atau sudah diproses.");
    }
    const houseId = String(reg.get("houseId"));
    const occupied = await tx.get(
      estate.collection("residents").where("houseId", "==", houseId).limit(1),
    );
    if (!occupied.empty) {
      throw new HttpsError("already-exists", `Rumah ${reg.get("houseNo")} sudah ditempati warga lain.`);
    }
    tx.set(residentRef, {
      name: reg.get("name"),
      houseId,
      houseNo: reg.get("houseNo"),
      phone: reg.get("phone"),
      email: reg.get("email"),
      uid,
      occupancy: reg.get("occupancy"),
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.doc(`users/${uid}`), {
      estateId,
      role: "warga",
      residentId: residentRef.id,
      name: reg.get("name"),
      mustChangePassword: false,
    });
    tx.update(regRef, {
      status: "disetujui",
      residentId: residentRef.id,
      reviewedAt: FieldValue.serverTimestamp(),
    });
  });
  return { residentId: residentRef.id };
});
