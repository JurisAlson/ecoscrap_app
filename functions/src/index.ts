import * as admin from "firebase-admin";
import { setGlobalOptions, logger } from "firebase-functions/v2";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as crypto from "crypto";

admin.initializeApp();
setGlobalOptions({ maxInstances: 10 });

async function sendPushToUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
) {
  const userSnap = await admin.firestore().collection("Users").doc(uid).get();
  if (!userSnap.exists) return;

  const token = (userSnap.data() as any)?.fcmToken as string | undefined;
  if (!token) return;

  await admin.messaging().send({
    token,
    notification: { title, body },
    data,
  });
}

/* ====================================================
    ADMIN-ONLY: Set user role in Firestore (for app routing)
==================================================== */
export const setUserRole = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const uid = request.data?.uid as string | undefined;
  let role = String(request.data?.role || "").trim().toLowerCase();

  if (role === "users") role = "user";
  if (role === "admins") role = "admin";
  if (role === "collectors") role = "collector";
  if (role === "junkshops") role = "junkshop";

  const allowed = ["user", "collector", "junkshop", "admin"];
  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");
  if (!allowed.includes(role)) throw new HttpsError("invalid-argument", "Invalid role");

  await admin.firestore().collection("Users").doc(uid).set({ Roles: role }, { merge: true });
  return { ok: true, uid, role };
});

/* ====================================================
   ADMIN-ONLY: Verify junkshop
==================================================== */
export const verifyJunkshop = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const uid = request.data?.uid as string | undefined;
  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");

  await admin.firestore().collection("Junkshop").doc(uid).set(
    {
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  await admin.firestore().collection("Users").doc(uid).set({ Roles: "junkshop" }, { merge: true });

  const user = await admin.auth().getUser(uid);
  const existing = user.customClaims || {};

  await admin.auth().setCustomUserClaims(uid, {
    ...existing,
    junkshop: true,
    collector: false,
    admin: existing.admin === true,
  });

  return { ok: true, uid };
});

/* ====================================================
   ADMIN-ONLY: Delete user (Auth + Firestore cleanup)
==================================================== */
export const adminDeleteUser = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const uid = request.data?.uid as string | undefined;
  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");

  const db = admin.firestore();

  try {
    await db.collection("Users").doc(uid).delete().catch(() => null);
    await db.collection("Junkshop").doc(uid).delete().catch(() => null);

    const permits = await db.collection("permitRequests").where("uid", "==", uid).get();
    const batch = db.batch();
    permits.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit().catch(() => null);

    await admin.auth().deleteUser(uid);
    return { ok: true, uid };
  } catch (err: any) {
    logger.error("adminDeleteUser error", { err: String(err), stack: err?.stack });
    throw new HttpsError("internal", err?.message || String(err));
  }
});

/* ====================================================
   ADMIN-ONLY: Grant/Revoke admin claim
==================================================== */
export const setAdminClaim = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid as string | undefined;
  const makeAdmin = request.data?.makeAdmin as boolean | undefined;

  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");
  if (typeof makeAdmin !== "boolean") throw new HttpsError("invalid-argument", "makeAdmin must be boolean");

  try {
    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};
    await admin.auth().setCustomUserClaims(uid, { ...existing, admin: makeAdmin });
    return { ok: true, uid, admin: makeAdmin };
  } catch (err: any) {
    throw new HttpsError("internal", err?.message || String(err));
  }
});

/* ====================================================
   Auto-sync claims whenever Users/{uid}.Roles changes
==================================================== */
export const syncRoleClaims = onDocumentWritten(
  { document: "Users/{uid}", region: "asia-southeast1" },
  async (event) => {
    try {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      if (!afterSnap?.exists) return;

      const before = (beforeSnap?.data() || {}) as any;
      const after = (afterSnap.data() || {}) as any;
      const uid = event.params.uid as string;

      const beforeRole = String(before.Roles || before.roles || "").trim().toLowerCase();
      let role = String(after.Roles || after.roles || "").trim().toLowerCase();

      if (role === "users") role = "user";
      if (role === "admins") role = "admin";
      if (role === "collectors") role = "collector";
      if (role === "junkshops") role = "junkshop";

      if (beforeRole === role) return;

      const roleClaims = {
        admin: role === "admin",
        collector: role === "collector",
        junkshop: role === "junkshop",
      };

      const existing = (await admin.auth().getUser(uid)).customClaims || {};
      await admin.auth().setCustomUserClaims(uid, { ...existing, ...roleClaims });

      logger.info("RBAC Claims synced", { uid, role, roleClaims });
    } catch (e: any) {
      logger.error("syncRoleClaims FAILED", { error: String(e), stack: e?.stack });
    }
  }
);

/* ====================================================
   KEYS
==================================================== */
function getKeysOrThrow() {
  const aesKeyB64 = process.env.PII_AES_KEY_B64;
  const hmacKeyB64 = process.env.PII_HMAC_KEY_B64;

  if (!aesKeyB64 || !hmacKeyB64) {
    throw new Error("Missing encryption secrets (PII_AES_KEY_B64 / PII_HMAC_KEY_B64).");
  }

  const AES_KEY = Buffer.from(aesKeyB64, "base64");
  const HMAC_KEY = Buffer.from(hmacKeyB64, "base64");

  if (AES_KEY.length !== 32) throw new Error("AES key must be 32 bytes (AES-256).");
  if (HMAC_KEY.length < 32) throw new Error("HMAC key too short (recommend >= 32 bytes).");

  return { AES_KEY, HMAC_KEY };
}

/* ====================================================
   NORMALIZERS
==================================================== */
function normalizeText(v: any) {
  return String(v).trim();
}
function normalizeEmail(v: any) {
  return String(v).trim().toLowerCase();
}
function normalizeMoney(v: any) {
  if (v === undefined || v === null) throw new Error("Missing money value");

  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error("Invalid money number");
    return v.toFixed(2);
  }

  if (typeof v === "string") {
    const cleaned = v.trim().replace(/[^\d.-]/g, "");
    const num = Number(cleaned);
    if (!Number.isFinite(num)) throw new Error(`Invalid money string: "${v}"`);
    return num.toFixed(2);
  }

  throw new Error(`Unsupported money type: ${typeof v}`);
}

/* ====================================================
   ENCRYPTION HELPERS
==================================================== */
function encryptNormalizedToFields(normalized: string, AES_KEY: Buffer, HMAC_KEY: Buffer, fieldPrefix: string) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", AES_KEY, nonce);

  const ciphertext = Buffer.concat([cipher.update(normalized, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  const lookup = crypto.createHmac("sha256", HMAC_KEY).update(normalized).digest("hex");

  return {
    [`${fieldPrefix}_enc`]: ciphertext.toString("base64"),
    [`${fieldPrefix}_nonce`]: nonce.toString("base64"),
    [`${fieldPrefix}_tag`]: tag.toString("base64"),
    [`${fieldPrefix}_lookup`]: lookup,
    piiVersion: 1,
    [`${fieldPrefix}SetAt`]: admin.firestore.FieldValue.serverTimestamp(),
  } as Record<string, any>;
}

function encryptNormalizedToFieldsNoTimestamp(normalized: string, AES_KEY: Buffer, HMAC_KEY: Buffer, fieldPrefix: string) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", AES_KEY, nonce);

  const ciphertext = Buffer.concat([cipher.update(normalized, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  const lookup = crypto.createHmac("sha256", HMAC_KEY).update(normalized).digest("hex");

  return {
    [`${fieldPrefix}_enc`]: ciphertext.toString("base64"),
    [`${fieldPrefix}_nonce`]: nonce.toString("base64"),
    [`${fieldPrefix}_tag`]: tag.toString("base64"),
    [`${fieldPrefix}_lookup`]: lookup,
  } as Record<string, any>;
}

function encryptStringToFields(plainText: any, AES_KEY: Buffer, HMAC_KEY: Buffer, fieldPrefix: string) {
  return encryptNormalizedToFields(normalizeText(plainText), AES_KEY, HMAC_KEY, fieldPrefix);
}
function encryptEmailToFields(email: any, AES_KEY: Buffer, HMAC_KEY: Buffer) {
  return encryptNormalizedToFields(normalizeEmail(email), AES_KEY, HMAC_KEY, "shopEmail");
}
function encryptMoneyToFields(value: any, AES_KEY: Buffer, HMAC_KEY: Buffer, fieldPrefix: string) {
  return encryptNormalizedToFields(normalizeMoney(value), AES_KEY, HMAC_KEY, fieldPrefix);
}
function encryptMoneyToFieldsForArray(value: any, AES_KEY: Buffer, HMAC_KEY: Buffer, fieldPrefix: string) {
  return encryptNormalizedToFieldsNoTimestamp(normalizeMoney(value), AES_KEY, HMAC_KEY, fieldPrefix);
}

/* ====================================================
   1) AUTO-ENCRYPT Junkshop.email ON CREATE/UPDATE
==================================================== */
export const encryptJunkshopEmailOnWrite = onDocumentWritten(
  {
    document: "Junkshop/{shopId}",
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data() as any;
    const { shopId } = event.params;

    const hasPlainEmail = typeof after?.email === "string" && after.email.trim() !== "";
    const alreadyEncrypted = !!after?.shopEmail_enc;
    if (!hasPlainEmail || alreadyEncrypted) return;

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();
      const encFields = encryptEmailToFields(after.email, AES_KEY, HMAC_KEY);

      await afterSnap.ref.update({
        ...encFields,
        email: admin.firestore.FieldValue.delete(),
      });

      logger.info("Encrypted Junkshop email successfully", { shopId });
    } catch (err: any) {
      logger.error("Encryption failed (Junkshop email)", { shopId, message: err?.message, stack: err?.stack });
    }
  }
);

/* ====================================================
   2) AUTO-ENCRYPT Transaction customerName + total + items[].subtotal
   ✅ FIXED so UI keeps name + totals
==================================================== */
export const encryptTransactionCustomerOnWrite = onDocumentWritten(
  {
    document: "Junkshop/{shopId}/transaction/{txId}",
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data() as any;
    const { shopId, txId } = event.params;

    const updatePayload: Record<string, any> = {};

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();

      // customerName (PII) -> encrypt + delete plaintext, but keep customerNameDisplay for UI
      if (!after?.customerName_enc && after?.customerName != null) {
        if (typeof after.customerName === "string" && after.customerName.trim() !== "") {
          Object.assign(updatePayload, encryptStringToFields(after.customerName, AES_KEY, HMAC_KEY, "customerName"));
          updatePayload.customerNameDisplay = after.customerName; // ✅ UI field
          updatePayload.customerName = admin.firestore.FieldValue.delete(); // ✅ remove plaintext PII
        }
      }

      // totalAmount -> encrypt but DO NOT delete plaintext (UI reads totalAmount)
      if (after?.totalAmount !== undefined && after?.totalAmount !== null && !after?.totalAmount_enc) {
        Object.assign(updatePayload, encryptMoneyToFields(after.totalAmount, AES_KEY, HMAC_KEY, "totalAmount"));
        // ✅ DO NOT delete totalAmount
      }

      // totalPrice (if you ever use it)
      if (after?.totalPrice !== undefined && after?.totalPrice !== null && !after?.totalPrice_enc) {
        Object.assign(updatePayload, encryptMoneyToFields(after.totalPrice, AES_KEY, HMAC_KEY, "totalPrice"));
        // ✅ DO NOT delete totalPrice
      }

      // items[].subtotal -> encrypt but DO NOT delete plaintext
      if (Array.isArray(after.items) && after.items.length > 0) {
        const newItems = after.items.map((it: any) => {
          const copy = { ...(it || {}) };

          if (copy.subtotal != null && !copy.subtotal_enc) {
            Object.assign(copy, encryptMoneyToFieldsForArray(copy.subtotal, AES_KEY, HMAC_KEY, "subtotal"));
            // ✅ DO NOT delete copy.subtotal
            copy.subtotalSetAtMs = Date.now();
          }
          return copy;
        });

        if (JSON.stringify(newItems) !== JSON.stringify(after.items)) {
          updatePayload.items = newItems;
        }
      }

      if (Object.keys(updatePayload).length === 0) return;

      await afterSnap.ref.update(updatePayload);
      logger.info("Encrypted transaction fields successfully", { shopId, txId });
    } catch (err: any) {
      logger.error("Encryption failed (transaction)", { shopId, txId, message: err?.message, stack: err?.stack });
    }
  }
);

/* ====================================================
   ADMIN-ONLY: SET/ENCRYPT Junkshop email via callable
==================================================== */
export const setJunkshopEmail = onCall(
  {
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
    if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

    const shopId = request.data?.shopId as string | undefined;
    const email = request.data?.email as string | undefined;

    if (!shopId || typeof shopId !== "string") throw new HttpsError("invalid-argument", "shopId is required.");
    if (!email || typeof email !== "string") throw new HttpsError("invalid-argument", "email is required.");

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();
      const encFields = encryptEmailToFields(email, AES_KEY, HMAC_KEY);

      const ref = admin.firestore().collection("Junkshop").doc(shopId);
      await ref.set(
        {
          ...encFields,
          email: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );

      return { ok: true };
    } catch (err: any) {
      throw new HttpsError("internal", String(err));
    }
  }
);

/* ====================================================
   Helper — subtract days
==================================================== */
function daysAgo(days: number) {
  const ms = days * 24 * 60 * 60 * 1000;
  return admin.firestore.Timestamp.fromDate(new Date(Date.now() - ms));
}

/* ====================================================
   AUTO add approvedAt when admin approves permit
==================================================== */
export const setApprovedAtOnApprove = onDocumentUpdated(
  {
    document: "permitRequests/{requestId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap || !afterSnap) return;

    const before = beforeSnap.data() as any;
    const after = afterSnap.data() as any;
    if (!before || !after) return;

    // Trigger only when it changes to approved
    if (before.approved !== true && after.approved === true) {
      logger.info("Approved -> set approvedAt + notify user", { requestId: event.params.requestId });

      // set approvedAt once
      if (!after.approvedAt) {
        await afterSnap.ref.update({
          approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const uid = String(after.uid || "").trim();
      if (uid) {
        await sendPushToUser(
          uid,
          "Junkshop Application Approved ✅",
          "Your junkshop application has been approved by the admin.",
          { type: "junkshop_approved", requestId: String(event.params.requestId) }
        );
      }
    }
  }
);

/* ====================================================
   SHARED CLEANUP LOGIC
==================================================== */
async function cleanupPermits() {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const cutoffUnapproved = daysAgo(30);
  const cutoffApproved = daysAgo(15);

  logger.info("Starting permit cleanup", {
    cutoffUnapproved: cutoffUnapproved.toDate().toISOString(),
    cutoffApproved: cutoffApproved.toDate().toISOString(),
  });

  const unapprovedSnap = await db
    .collection("permitRequests")
    .where("approved", "==", false)
    .where("submittedAt", "<=", cutoffUnapproved)
    .limit(200)
    .get();

  const approvedSnap = await db
    .collection("permitRequests")
    .where("approved", "==", true)
    .where("approvedAt", "<=", cutoffApproved)
    .limit(200)
    .get();

  const docsToDelete = [...unapprovedSnap.docs, ...approvedSnap.docs];

  if (docsToDelete.length === 0) {
    logger.info("No permits eligible for cleanup");
    return { deleted: 0 };
  }

  logger.info("Permits found", {
    total: docsToDelete.length,
    unapproved: unapprovedSnap.size,
    approved: approvedSnap.size,
  });

  let deleted = 0;

  for (const doc of docsToDelete) {
    const data = doc.data() as any;
    const permitPath = data.permitPath as string | undefined;

    try {
      if (permitPath) {
        await bucket.file(permitPath).delete({ ignoreNotFound: true } as any);
      }

      await doc.ref.update({
        permitExpired: true,
        permitDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      deleted++;
      logger.info("Permit file removed", { requestId: doc.id, permitPath });
    } catch (err: any) {
      logger.error("Permit deletion failed", { requestId: doc.id, err: String(err) });
    }
  }

  logger.info("Cleanup finished", { deleted });
  return { deleted };
}

/* ====================================================
   SCHEDULED CLEANUP (Runs every 24h)
==================================================== */
export const cleanupPermitsByRetention = onSchedule(
  {
    schedule: "every 24 hours",
    region: "asia-southeast1",
    timeZone: "Asia/Manila",
  },
  async () => {
    const result = await cleanupPermits();
    logger.info("Scheduled cleanup result", result);
  }
);

/* ====================================================
   MANUAL CLEANUP (FOR TESTING)
==================================================== */
export const runPermitCleanupNow = onRequest({ region: "asia-southeast1" }, async (req, res) => {
  try {
    const result = await cleanupPermits();
    res.status(200).json({ ok: true, ...result });
  } catch (err: any) {
    logger.error("Manual cleanup crashed", { err: String(err) });
    res.status(500).json({ ok: false, error: String(err) });
  }
});

/* ====================================================
   INVENTORY DEDUCTION (UNCHANGED)
==================================================== */
export const deductInventoryOnTransactionCreate = onDocumentCreated(
  {
    document: "Junkshop/{shopId}/transaction/{txId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const { shopId } = event.params;
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    if (!data || !Array.isArray(data.items)) return;

    const txType = String(data.transactionType || "sale").toLowerCase();
    if (txType !== "sale") return;

    // prevent double-run
    if (data.inventoryDeducted === true) return;

    const db = admin.firestore();

    // helpers
    /*const EPS = 0.0001; // tiny tolerance for float errors
    const round2 = (n: number) => Math.round(n * 100) / 100;*/

    await db.runTransaction(async (t) => {
        for (const item of data.items) {
            const inventoryRef = db
            .collection("Junkshop")
            .doc(shopId)
            .collection("inventory")
            .doc(item.inventoryDocId);

            const inventorySnap = await t.get(inventoryRef);
            if (!inventorySnap.exists) continue;

            const currentKg = Number((inventorySnap.data() as any).unitsKg) || 0;
            const newKg = Math.max(currentKg - Number(item.weightKg), 0);

            if (newKg <= 0) {
            // ✅ DELETE if zero
            t.delete(inventoryRef);
            } else {
            t.update(inventoryRef, {
                unitsKg: newKg,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            }
        }

        t.update(snap.ref, {
            inventoryDeducted: true,
            inventoryDeductedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        });
    }
);

export const notifyCollectorApproved = onDocumentUpdated(
  { document: "Users/{uid}", region: "asia-southeast1" },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap || !afterSnap) return;

    const before = beforeSnap.data() as any;
    const after = afterSnap.data() as any;

    // Your app uses BOTH "Roles" and "role" in different places
    const beforeRole = String(before?.Roles || before?.role || "").trim().toLowerCase();
    const afterRole = String(after?.Roles || after?.role || "").trim().toLowerCase();

    // Only notify on transition to collector
    if (beforeRole !== "collector" && afterRole === "collector") {
      const uid = String(event.params.uid);

      await sendPushToUser(
        uid,
        "Collector Application Approved",
        "Your collector application has been approved by the admin.",
        { type: "collector_approved", uid }
      );

      logger.info("Collector approval notified", { uid });
    }
  }
);



export const addInventoryOnBuyCreate = onDocumentCreated(
  {
    document: "Junkshop/{shopId}/transaction/{txId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const { shopId } = event.params;
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    if (!data || !Array.isArray(data.items)) return;

    const txType = String(data.transactionType || "sale").toLowerCase();
    if (txType !== "buy") return;

    // prevent double-run
    if (data.inventoryAdded === true) return;

    const db = admin.firestore();

    await db.runTransaction(async (t) => {
      for (const item of data.items) {
        const weightKg = Number(item.weightKg) || 0;
        if (weightKg <= 0) continue;

        const category = String(item.category || "").trim();
        const subCategory = String(item.subCategory || "").trim();

        if (!category || !subCategory) continue;

        // ✅ merge strategy: 1 inventory doc per category + subCategory
        const invQuery = db
          .collection("Junkshop")
          .doc(shopId)
          .collection("inventory")
          .where("category", "==", category)
          .where("subCategory", "==", subCategory)
          .limit(1);

        const qSnap = await t.get(invQuery);

        if (!qSnap.empty) {
          // update existing
          const invDoc = qSnap.docs[0];
          const currentKg = Number((invDoc.data() as any).unitsKg) || 0;
          const newKg = currentKg + weightKg;

          t.update(invDoc.ref, {
            unitsKg: newKg,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          // create new
          const invRef = db
            .collection("Junkshop")
            .doc(shopId)
            .collection("inventory")
            .doc(); // auto id

          const derivedName = `${category} • ${subCategory}`;

          t.set(invRef, {
            name: derivedName,
            category,
            subCategory,
            notes: "",
            unitsKg: weightKg,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      // mark transaction as processed
      t.update(snap.ref, {
        inventoryAdded: true,
        inventoryAddedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
);