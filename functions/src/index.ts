/**
 * Cloud Functions untuk Amani Living.
 *
 *  - createEstate        (callable)  pengelola membuat perumahan baru (multi-perumahan)
 *  - createResident      (callable)  pengelola menambah warga + membuat akun login
 *  - listRegistrationEstates / getRegistrationOptions (callable, tanpa login)
 *                                    daftar perumahan & rumah tersedia untuk pendaftaran
 *  - submitRegistration  (callable)  calon warga mengirim pendaftaran mandiri
 *  - approveRegistration (callable)  pengelola menyetujui pendaftaran -> akun jadi warga
 *  - addHouseholdMember / removeHouseholdMember (callable)
 *                                    akun anggota rumah (keluarga/penyewa)
 *  - addStaff / removeStaff (callable) pemilik mengelola tim pengelola
 *  - resetResidentPassword (callable) pengelola membuat password sementara baru
 *                                    untuk warga yang lupa password
 *  - payBill             (callable)  warga membayar tagihan (SIMULASI, lihat catatan)
 *  - generateMonthlyBills (terjadwal) membuat tagihan IPL tiap tanggal 1, 01.00 WIB
 *  - notifyAnnouncement / notifyBillCreated / notifyBillPaid (trigger Firestore)
 *  - remindBills         (terjadwal, harian 09.00 WIB) pengingat H-2 & H+2 jatuh tempo
 *                        -> notifikasi push (FCM) ke perangkat warga
 *
 * Butuh paket Firebase "Blaze" untuk deploy.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, QueryDocumentSnapshot } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { randomBytes } from "node:crypto";

initializeApp();
setGlobalOptions({ region: "asia-southeast2", maxInstances: 10 });

const db = getFirestore();
const DEFAULT_FEE = 250000;
const DEFAULT_DUE_DAY = 10;

/** Tanggal jatuh tempo IPL perumahan (1–28). */
function dueDayOf(estate: FirebaseFirestore.DocumentSnapshot): number {
  const d = Number(estate.get("billDueDay") ?? DEFAULT_DUE_DAY);
  return Number.isInteger(d) && d >= 1 && d <= 28 ? d : DEFAULT_DUE_DAY;
}

/** "2026-11" + 5 -> "2026-11-05" */
function dueDateKey(period: string, day: number): string {
  return `${period}-${String(day).padStart(2, "0")}`;
}

type Profile = {
  estateId: string;
  /** Pengelola: semua perumahan yang dikelola (estateId = perumahan utama). */
  estateIds?: string[];
  role: "warga" | "pengelola" | "pendaftar";
  residentId?: string;
  name: string;
  /** "anggota" untuk anggota rumah; kepala keluarga tidak punya field ini. */
  householdRole?: "anggota";
};

async function profileOf(uid: string | undefined): Promise<Profile & { uid: string }> {
  if (!uid) throw new HttpsError("unauthenticated", "Silakan login terlebih dahulu.");
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Akun tidak terdaftar.");
  return { ...(snap.data() as Profile), uid };
}

type Permission =
  | "masterData"
  | "residents"
  | "billing"
  | "complaints"
  | "visitors"
  | "announcements"
  | "renovations"
  | "renovationLogs";

/**
 * Hak akses pengelola di sebuah perumahan. Pengelola yang tidak tercatat di
 * estates/{e}/staff dianggap pemilik (akun lama), sama seperti firestore.rules.
 */
async function staffAccess(me: Profile & { uid: string }, estateId: string) {
  if (!managesEstate(me, estateId)) return { admin: false, owner: false, perms: new Set<string>() };
  const s = await db.doc(`estates/${estateId}/staff/${me.uid}`).get();
  if (!s.exists || s.get("isOwner") === true) {
    return { admin: true, owner: true, perms: new Set<string>() };
  }
  return { admin: true, owner: false, perms: new Set<string>(s.get("permissions") ?? []) };
}

async function hasPermission(me: Profile & { uid: string }, estateId: string, perm: Permission) {
  const a = await staffAccess(me, estateId);
  return a.owner || a.perms.has(perm);
}

async function requirePermission(me: Profile & { uid: string }, estateId: string, perm: Permission, what: string) {
  if (!(await hasPermission(me, estateId, perm))) {
    throw new HttpsError("permission-denied", `Anda tidak punya akses untuk ${what}.`);
  }
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
  const billDueDay = Number(data.billDueDay ?? DEFAULT_DUE_DAY);
  if (!Number.isInteger(billDueDay) || billDueDay < 1 || billDueDay > 28) {
    throw new HttpsError("invalid-argument", "Tanggal jatuh tempo harus 1–28.");
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
    billDueDay,
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
  await requirePermission(me, estateId, "residents", "menambah warga");
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
      const dueDate = dueDateKey(period, dueDayOf(estate));
      // Tarif per tipe rumah: rumah -> blok -> tipe.monthlyFee.
      const [residents, houses, blocks, types] = await Promise.all([
        estate.ref.collection("residents").get(),
        estate.ref.collection("houses").get(),
        estate.ref.collection("blocks").get(),
        estate.ref.collection("houseTypes").get(),
      ]);
      const typeFee = new Map<string, number>();
      types.docs.forEach((t) => {
        const f = Number(t.get("monthlyFee"));
        if (Number.isInteger(f) && f > 0) typeFee.set(t.id, f);
      });
      const blockType = new Map(blocks.docs.map((b) => [b.id, String(b.get("typeId") ?? "")]));
      const houseBlock = new Map(houses.docs.map((h) => [h.id, String(h.get("blockId") ?? "")]));
      const feeFor = (houseId: unknown): number => {
        if (typeof houseId !== "string") return fee;
        const typeId = blockType.get(houseBlock.get(houseId) ?? "") ?? "";
        return typeFee.get(typeId) ?? fee;
      };

      const writer = db.bulkWriter();
      for (const r of residents.docs) {
        // ID deterministik -> create() gagal bila tagihan bulan ini sudah ada (aman diulang).
        writer
          .create(estate.ref.collection("bills").doc(`${r.id}_${period}`), {
            residentId: r.id,
            period,
            amount: feeFor(r.get("houseId")),
            dueDate,
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

/**
 * Status rumah untuk pendaftaran: `occupied` = rumah -> residentId penghuni;
 * `pending` = rumah kosong yang sedang diajukan pendaftar lain (warga baru).
 */
async function houseStatus(estateId: string, exceptUid?: string) {
  const estate = db.doc(`estates/${estateId}`);
  const [residents, pendingRegs] = await Promise.all([
    estate.collection("residents").select("houseId").get(),
    estate.collection("registrations").where("status", "==", "menunggu").get(),
  ]);
  const occupied = new Map<string, string>();
  residents.docs.forEach((d) => {
    const h = d.get("houseId");
    if (typeof h === "string") occupied.set(h, d.id);
  });
  const pending = new Set<string>();
  pendingRegs.docs.forEach((d) => {
    if (d.id !== exceptUid && d.get("kind") !== "gabung") pending.add(String(d.get("houseId")));
  });
  return { occupied, pending };
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
  const [clusters, types, blocks, houses, status] = await Promise.all([
    estate.collection("clusters").get(),
    estate.collection("houseTypes").get(),
    estate.collection("blocks").get(),
    estate.collection("houses").get(),
    houseStatus(estateId, req.auth?.uid),
  ]);
  const plain = (d: FirebaseFirestore.QueryDocumentSnapshot) => ({ id: d.id, ...d.data() });
  return {
    clusters: clusters.docs.map(plain),
    types: types.docs.map(plain),
    blocks: blocks.docs.map(plain),
    // Hanya status rumah; nama/data penghuni tidak dikirim.
    houses: houses.docs.map((d) => ({
      ...plain(d),
      available: !status.occupied.has(d.id) && !status.pending.has(d.id),
      occupied: status.occupied.has(d.id),
    })),
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
  const relation = data.relation == null ? null : String(data.relation);
  if (relation != null && !RELATIONS.includes(relation)) {
    throw new HttpsError("invalid-argument", "Hubungan keluarga tidak valid.");
  }

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
  const status = await houseStatus(estateId, uid);
  const householdId = status.occupied.get(houseId) ?? null;
  if (relation != null) {
    // Gabung ke rumah berpenghuni sebagai anggota rumah.
    if (householdId == null) {
      throw new HttpsError("failed-precondition", "Rumah ini masih kosong. Daftar sebagai warga baru.");
    }
    const count = await estate.collection("members").where("residentId", "==", householdId).count().get();
    if (count.data().count >= MAX_MEMBERS) {
      throw new HttpsError("resource-exhausted", "Anggota rumah ini sudah penuh.");
    }
  } else if (householdId != null || status.pending.has(houseId)) {
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
    kind: relation != null ? "gabung" : "baru",
    relation,
    residentId: relation != null ? householdId : null,
    status: "menunggu",
    note: "",
    createdAt: FieldValue.serverTimestamp(),
    reviewedAt: null,
  });
  batch.set(userRef, { estateId, role: "pendaftar", name });
  await batch.commit();
  return { ok: true };
});

/**
 * Menyetujui pendaftaran.
 *  - Warga baru: oleh pengelola; membuat data warga di rumah kosong.
 *  - Gabung: oleh pengelola atau kepala keluarga rumah tujuan; membuat akun
 *    anggota rumah.
 */
export const approveRegistration = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const uid = requireText(data.uid, "uid");
  const estate = db.doc(`estates/${estateId}`);
  const regRef = estate.collection("registrations").doc(uid);

  const first = await regRef.get();
  if (!first.exists) throw new HttpsError("not-found", "Pendaftaran tidak ditemukan.");
  const isJoin = first.get("kind") === "gabung";
  const householdId = String(first.get("residentId") ?? "");
  const allowed = isJoin
    ? await canManageHousehold(me, estateId, householdId)
    : await hasPermission(me, estateId, "residents");
  if (!allowed) {
    throw new HttpsError("permission-denied", "Anda tidak berhak menyetujui pendaftaran ini.");
  }

  const residentRef = estate.collection("residents").doc();
  await db.runTransaction(async (tx) => {
    const reg = await tx.get(regRef);
    if (reg.get("status") !== "menunggu") {
      throw new HttpsError("failed-precondition", "Pendaftaran sudah diproses.");
    }
    if (isJoin) {
      const household = await tx.get(estate.collection("residents").doc(householdId));
      if (!household.exists) throw new HttpsError("not-found", "Data rumah tidak ditemukan.");
      const current = await tx.get(estate.collection("members").where("residentId", "==", householdId));
      if (current.size >= MAX_MEMBERS) {
        throw new HttpsError("resource-exhausted", "Anggota rumah sudah penuh.");
      }
      tx.set(estate.collection("members").doc(uid), {
        residentId: householdId,
        name: reg.get("name"),
        relation: reg.get("relation") ?? "lainnya",
        phone: reg.get("phone"),
        email: reg.get("email"),
        addedBy: req.auth!.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.set(db.doc(`users/${uid}`), {
        estateId,
        role: "warga",
        residentId: householdId,
        name: reg.get("name"),
        householdRole: "anggota",
        relation: reg.get("relation") ?? "lainnya",
        mustChangePassword: false,
      });
      tx.update(regRef, { status: "disetujui", reviewedAt: FieldValue.serverTimestamp() });
      return;
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
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Anggota rumah (keluarga / penyewa)
// ---------------------------------------------------------------------------

const RELATIONS = ["pasangan", "anak", "orangTua", "saudara", "penyewa", "lainnya"];
const MAX_MEMBERS = 6;

/** Pengelola dengan hak warga, atau kepala keluarga rumah tersebut. */
async function canManageHousehold(
  me: Profile & { uid: string },
  estateId: string,
  residentId: string,
): Promise<boolean> {
  if (await hasPermission(me, estateId, "residents")) return true;
  return (
    me.role === "warga" &&
    me.estateId === estateId &&
    me.residentId === residentId &&
    me.householdRole !== "anggota"
  );
}

export const addHouseholdMember = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const residentId = requireText(data.residentId, "residentId");
  if (!(await canManageHousehold(me, estateId, residentId))) {
    throw new HttpsError("permission-denied", "Hanya kepala keluarga atau pengelola yang bisa menambah anggota.");
  }
  const name = requireText(data.name, "Nama", 100);
  const email = requireText(data.email, "Email", 120).toLowerCase();
  const phone = typeof data.phone === "string" ? data.phone.trim().slice(0, 20) : "";
  const relation = String(data.relation ?? "");
  if (!RELATIONS.includes(relation)) {
    throw new HttpsError("invalid-argument", "Hubungan keluarga tidak valid.");
  }

  const estate = db.doc(`estates/${estateId}`);
  const resident = await estate.collection("residents").doc(residentId).get();
  if (!resident.exists) throw new HttpsError("not-found", "Data rumah tidak ditemukan.");
  const count = await estate.collection("members").where("residentId", "==", residentId).count().get();
  if (count.data().count >= MAX_MEMBERS) {
    throw new HttpsError("resource-exhausted", `Maksimal ${MAX_MEMBERS} anggota per rumah.`);
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

  const batch = db.batch();
  batch.set(estate.collection("members").doc(uid), {
    residentId,
    name,
    relation,
    phone,
    email,
    addedBy: req.auth!.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.doc(`users/${uid}`), {
    estateId,
    role: "warga",
    residentId,
    name,
    householdRole: "anggota",
    relation,
    mustChangePassword: true,
  });
  await batch.commit();
  return { uid, tempPassword };
});

export const removeHouseholdMember = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const uid = requireText(data.uid, "uid");
  const ref = db.doc(`estates/${estateId}/members/${uid}`);
  const member = await ref.get();
  if (!member.exists) throw new HttpsError("not-found", "Anggota tidak ditemukan.");
  if (!(await canManageHousehold(me, estateId, String(member.get("residentId"))))) {
    throw new HttpsError("permission-denied", "Hanya kepala keluarga atau pengelola yang bisa menghapus anggota.");
  }
  const batch = db.batch();
  batch.delete(ref);
  batch.delete(db.doc(`users/${uid}`));
  await batch.commit();
  try {
    await getAuth().deleteUser(uid);
  } catch (e: unknown) {
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
  }
  return { ok: true };
});

// ---------------------------------------------------------------------------

/**
 * Pengelola mereset password akun warga (kepala keluarga atau anggota rumah)
 * yang lupa password. Membuat password sementara baru, mengeluarkan semua
 * sesi login lama, dan mewajibkan ganti password saat login berikutnya.
 */
export const resetResidentPassword = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const residentId = requireText(data.residentId, "residentId");
  await requirePermission(me, estateId, "residents", "mereset password warga");

  const estate = db.doc(`estates/${estateId}`);
  let uid: string | undefined;
  if (typeof data.memberUid === "string" && data.memberUid !== "") {
    // Anggota rumah: harus benar-benar anggota rumah ini.
    const member = await estate.collection("members").doc(data.memberUid).get();
    if (!member.exists || member.get("residentId") !== residentId) {
      throw new HttpsError("not-found", "Anggota rumah tidak ditemukan.");
    }
    uid = member.id;
  } else {
    const resident = await estate.collection("residents").doc(residentId).get();
    if (!resident.exists) throw new HttpsError("not-found", "Data warga tidak ditemukan.");
    uid = resident.get("uid") as string | undefined;
    if (!uid) {
      // Data lama tanpa field uid: cari akun kepala keluarga lewat profil.
      const users = await db
        .collection("users")
        .where("estateId", "==", estateId)
        .where("residentId", "==", residentId)
        .where("role", "==", "warga")
        .get();
      uid = users.docs.find((d) => d.get("householdRole") !== "anggota")?.id;
    }
  }
  if (!uid) throw new HttpsError("not-found", "Warga ini belum punya akun login.");

  // Hanya akun warga di perumahan ini yang boleh direset (bukan pengelola lain).
  const profile = await db.doc(`users/${uid}`).get();
  if (!profile.exists || profile.get("role") !== "warga" || profile.get("estateId") !== estateId) {
    throw new HttpsError("permission-denied", "Akun ini bukan warga perumahan Anda.");
  }

  const tempPassword = randomBytes(9).toString("base64url");
  try {
    await getAuth().updateUser(uid, { password: tempPassword });
  } catch (e: unknown) {
    if ((e as { code?: string }).code === "auth/user-not-found") {
      throw new HttpsError("not-found", "Akun login warga ini sudah tidak ada.");
    }
    throw e;
  }
  await getAuth().revokeRefreshTokens(uid);
  await profile.ref.update({ mustChangePassword: true });
  const user = await getAuth().getUser(uid);
  return { email: user.email ?? "", tempPassword };
});

// ---------------------------------------------------------------------------
// Notifikasi push (Firebase Cloud Messaging)
// ---------------------------------------------------------------------------
//
// Token perangkat disimpan aplikasi di users/{uid}/devices/{token}.
// Preferensi di users/{uid}.notifPrefs { announcements, bills } (default aktif).
// Pengiriman per pengguna (bukan topik publik) agar info tagihan tidak bocor.

type NotifKind = "announcements" | "bills";

const MONTHS = [
  "Januari", "Februari", "Maret", "April", "Mei", "Juni",
  "Juli", "Agustus", "September", "Oktober", "November", "Desember",
];

/** "2026-11" -> "November 2026" */
function monthLabel(period: string): string {
  const [y, m] = period.split("-").map(Number);
  return `${MONTHS[(m || 1) - 1]} ${y}`;
}

function rupiah(n: number): string {
  return `Rp ${new Intl.NumberFormat("id-ID").format(n)}`;
}

/** Warga (termasuk anggota rumah) di perumahan; opsional satu rumah saja. */
async function residentUsers(estateId: string, residentId?: string) {
  let q = db.collection("users").where("estateId", "==", estateId).where("role", "==", "warga");
  if (residentId) q = q.where("residentId", "==", residentId);
  return (await q.get()).docs;
}

async function deviceTokens(users: QueryDocumentSnapshot[], kind: NotifKind) {
  const wanted = users.filter((u) => u.get(`notifPrefs.${kind}`) !== false);
  const lists = await Promise.all(
    wanted.map(async (u) => (await u.ref.collection("devices").get()).docs.map((d) => d.ref)),
  );
  return lists.flat();
}

/** Kirim ke banyak token; token yang sudah tidak valid dihapus. */
async function push(
  users: QueryDocumentSnapshot[],
  kind: NotifKind,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const refs = await deviceTokens(users, kind);
  for (let i = 0; i < refs.length; i += 500) {
    const chunk = refs.slice(i, i + 500);
    const res = await getMessaging().sendEachForMulticast({
      tokens: chunk.map((r) => r.id),
      notification: { title, body },
      data,
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });
    await Promise.all(
      res.responses.map((r, j) => {
        const code = r.error?.code ?? "";
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          return chunk[j].delete();
        }
        return undefined;
      }),
    );
  }
  return refs.length;
}

export const notifyAnnouncement = onDocumentCreated(
  "estates/{estateId}/announcements/{announcementId}",
  async (event) => {
    const a = event.data;
    if (!a) return;
    const estateId = event.params.estateId;
    const body = String(a.get("body") ?? "");
    await push(
      await residentUsers(estateId),
      "announcements",
      `📢 ${a.get("title") ?? "Pengumuman baru"}`,
      body.length > 140 ? `${body.slice(0, 137)}…` : body,
      { type: "announcement", estateId, id: a.id },
    );
  },
);

export const notifyBillCreated = onDocumentCreated(
  "estates/{estateId}/bills/{billId}",
  async (event) => {
    const b = event.data;
    if (!b || b.get("status") !== "belumBayar") return;
    const estateId = event.params.estateId;
    const period = String(b.get("period"));
    await push(
      await residentUsers(estateId, String(b.get("residentId"))),
      "bills",
      `Tagihan IPL ${monthLabel(period)}`,
      `${rupiah(Number(b.get("amount")))} sudah terbit. Jatuh tempo ${dateLabel(billDueDate(b))}.`,
      { type: "bill", estateId, id: b.id },
    );
  },
);

export const notifyBillPaid = onDocumentUpdated(
  "estates/{estateId}/bills/{billId}",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;
    if (before.get("status") === "lunas" || after.get("status") !== "lunas") return;
    const estateId = event.params.estateId;
    await push(
      await residentUsers(estateId, String(after.get("residentId"))),
      "bills",
      "Pembayaran diterima ✅",
      `IPL ${monthLabel(String(after.get("period")))} ${rupiah(Number(after.get("amount")))} lunas. Terima kasih!`,
      { type: "bill", estateId, id: after.id },
    );
  },
);

/** Jatuh tempo tagihan ("YYYY-MM-DD"); tagihan lama tanpa field: tanggal 10. */
function billDueDate(bill: FirebaseFirestore.DocumentSnapshot): string {
  const d = bill.get("dueDate");
  return typeof d === "string" ? d : dueDateKey(String(bill.get("period")), DEFAULT_DUE_DAY);
}

/** "2026-11-05" -> "5 November 2026" */
function dateLabel(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  return `${d} ${MONTHS[(m || 1) - 1]} ${y}`;
}

/** Tanggal hari ini (WIB) digeser [days] hari, sebagai "YYYY-MM-DD". */
function jakartaDayKey(offsetDays = 0): string {
  const shifted = new Date(Date.now() + offsetDays * 86400000);
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(shifted);
}

/**
 * Harian 09.00 WIB: pengingat H-2 sebelum jatuh tempo, dan pemberitahuan
 * H+2 setelah jatuh tempo, untuk tagihan yang belum dibayar.
 */
export const remindBills = onSchedule(
  { schedule: "0 9 * * *", timeZone: "Asia/Jakarta" },
  async () => {
    const dueSoon = jakartaDayKey(2); // jatuh tempo lusa
    const overdue = jakartaDayKey(-2); // jatuh tempo 2 hari lalu
    const estates = await db.collection("estates").get();
    for (const estate of estates.docs) {
      const unpaid = await estate.ref.collection("bills").where("status", "==", "belumBayar").get();
      for (const bill of unpaid.docs) {
        const due = billDueDate(bill);
        if (due !== dueSoon && due !== overdue) continue;
        const late = due === overdue;
        const period = String(bill.get("period"));
        const amount = rupiah(Number(bill.get("amount")));
        await push(
          await residentUsers(estate.id, String(bill.get("residentId"))),
          "bills",
          late ? `IPL ${monthLabel(period)} lewat jatuh tempo` : `Pengingat: IPL ${monthLabel(period)}`,
          late
            ? `${amount} belum dibayar (jatuh tempo ${dateLabel(due)}). Mohon segera dilunasi.`
            : `${amount} jatuh tempo ${dateLabel(due)}. Bayar lewat aplikasi.`,
          { type: "bill", estateId: estate.id, id: bill.id },
        );
      }
    }
  },
);

// ---------------------------------------------------------------------------
// Tim pengelola (khusus pemilik)
// ---------------------------------------------------------------------------

async function requireOwner(me: Profile & { uid: string }, estateId: string) {
  const a = await staffAccess(me, estateId);
  if (!a.owner) {
    throw new HttpsError("permission-denied", "Hanya pemilik yang bisa mengatur tim pengelola.");
  }
}

/**
 * Menambah anggota tim pengelola. roleId kosong = pemilik. Email yang sudah
 * punya akun pengelola cukup ditambahkan ke perumahan ini; email baru dibuat
 * akunnya dengan password sementara (wajib diganti saat login).
 */
export const addStaff = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  await requireOwner(me, estateId);
  const name = requireText(data.name, "Nama", 100);
  const email = requireText(data.email, "Email", 120).toLowerCase();
  const phone = typeof data.phone === "string" ? data.phone.trim().slice(0, 20) : "";
  const estate = db.doc(`estates/${estateId}`);

  let roleName = "";
  let permissions: string[] = [];
  const roleId = typeof data.roleId === "string" && data.roleId !== "" ? data.roleId : null;
  if (roleId) {
    const role = await estate.collection("adminRoles").doc(roleId).get();
    if (!role.exists) throw new HttpsError("not-found", "Level akses tidak ditemukan.");
    roleName = String(role.get("name") ?? "");
    permissions = [...(role.get("permissions") ?? [])].sort();
  }

  let uid: string;
  let tempPassword: string | null = null;
  try {
    const existing = await getAuth().getUserByEmail(email);
    uid = existing.uid;
    const profile = await db.doc(`users/${uid}`).get();
    if (profile.exists && profile.get("role") !== "pengelola") {
      throw new HttpsError("already-exists", "Email ini dipakai akun warga. Gunakan email lain.");
    }
    await db.doc(`users/${uid}`).set(
      {
        role: "pengelola",
        estateId: profile.get("estateId") ?? estateId,
        estateIds: FieldValue.arrayUnion(estateId),
        name: profile.get("name") ?? name,
      },
      { merge: true },
    );
  } catch (e: unknown) {
    if (e instanceof HttpsError) throw e;
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    tempPassword = randomBytes(9).toString("base64url");
    const user = await getAuth().createUser({ email, password: tempPassword, displayName: name });
    uid = user.uid;
    await db.doc(`users/${uid}`).set({
      role: "pengelola",
      estateId,
      estateIds: [estateId],
      name,
      mustChangePassword: true,
    });
  }

  await estate.collection("staff").doc(uid).set({
    name,
    email,
    phone,
    isOwner: roleId == null,
    roleId,
    roleName,
    permissions,
    addedBy: me.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { uid, tempPassword };
});

/** Mengeluarkan anggota tim dari perumahan (akun tetap ada bila masih
 *  mengelola perumahan lain; bila tidak, akunnya dihapus). */
export const removeStaff = onCall(async (req) => {
  const me = await profileOf(req.auth?.uid);
  const data = req.data ?? {};
  const estateId = requireText(data.estateId, "estateId");
  const uid = requireText(data.uid, "uid");
  await requireOwner(me, estateId);
  if (uid === me.uid) throw new HttpsError("failed-precondition", "Tidak bisa mengeluarkan diri sendiri.");

  const estate = db.doc(`estates/${estateId}`);
  const target = await estate.collection("staff").doc(uid).get();
  if (target.get("isOwner") === true) {
    const owners = await estate.collection("staff").where("isOwner", "==", true).count().get();
    if (owners.data().count <= 1) {
      throw new HttpsError("failed-precondition", "Harus ada minimal satu pemilik.");
    }
  }
  await target.ref.delete();

  const profileRef = db.doc(`users/${uid}`);
  const profile = await profileRef.get();
  if (!profile.exists || profile.get("role") !== "pengelola") return { ok: true };
  const remaining = new Set<string>([profile.get("estateId"), ...(profile.get("estateIds") ?? [])]);
  remaining.delete(estateId);
  remaining.delete(undefined as unknown as string);
  if (remaining.size === 0) {
    await profileRef.delete();
    try {
      await getAuth().deleteUser(uid);
    } catch (e: unknown) {
      if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    }
  } else {
    const list = [...remaining];
    await profileRef.update({ estateIds: list, estateId: list[0] });
  }
  return { ok: true };
});
