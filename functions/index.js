const admin = require("firebase-admin");
const { logger } = require("firebase-functions/v2");
const crypto = require("crypto");

const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

admin.initializeApp();

/* ====================================================
    ADMIN-ONLY: Set user role in Firestore (for app routing)
==================================================== */
exports.setUserRole = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  let role = String(request.data?.role || "").trim().toLowerCase();

  // normalize common variants
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
exports.verifyJunkshop = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");

  // 1) Mark junkshop verified in Users/{uid}
  await admin.firestore().collection("Users").doc(uid).set(
    {
      Roles: "junkshop",
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // 2) Keep Auth custom claims in sync
  const user = await admin.auth().getUser(uid);
  const existing = user.customClaims || {};

  await admin.auth().setCustomUserClaims(uid, {
    ...existing,
    junkshop: true,
    collector: false,
    admin: existing.admin === true, // preserve admin
  });

  return { ok: true, uid };
});

exports.reviewPermitRequest = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

  const uid = String(request.data?.uid || "").trim();
  const decision = String(request.data?.decision || "").trim().toLowerCase(); // approved | rejected

  if (!uid) throw new HttpsError("invalid-argument", "uid required");
  if (!["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "decision must be approved|rejected");
  }

  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const reqRef = db.collection("permitRequests").doc(uid);
  const userRef = db.collection("Users").doc(uid);

  const reviewedByUid = request.auth.uid;

  // Read request doc
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new HttpsError("not-found", "permit request not found");

  const reqData = reqSnap.data() || {};
  const permitPath = String(reqData.permitPath || "").trim();

  // Update Firestore (request + user)
  const batch = db.batch();

  batch.set(reqRef, {
    status: decision,
    approved: decision === "approved",
    reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
    reviewedByUid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(decision === "approved" ? { approvedAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
  }, { merge: true });

  if (decision === "approved") {
    batch.set(userRef, {
      role: "junkshop",
      Roles: "junkshop",
      junkshopStatus: "approved",
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      activePermitRequestId: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } else {
    batch.set(userRef, {
      role: "user",
      Roles: "user",
      junkshopStatus: "rejected",
      activePermitRequestId: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await batch.commit();

  // Delete file from Storage after decision
  if (permitPath) {
    await bucket.file(permitPath).delete({ ignoreNotFound: true });
  }

  // Sync claims if approved
  if (decision === "approved") {
    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};
    await admin.auth().setCustomUserClaims(uid, { ...existing, junkshop: true, collector: false });
  }

  return { ok: true, uid, decision };
});

/* ====================================================
   OWNER/ADMIN-ONLY: Grant/Revoke admin claim
==================================================== */
exports.setAdminClaim = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  const makeAdmin = request.data?.makeAdmin;

  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");
  if (typeof makeAdmin !== "boolean") throw new HttpsError("invalid-argument", "makeAdmin must be boolean");

  try {
    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};

    await admin.auth().setCustomUserClaims(uid, {
      ...existing,
      admin: makeAdmin,
    });

    return { ok: true, uid, admin: makeAdmin };
  } catch (err) {
    throw new HttpsError("internal", err?.message || String(err));
  }
});

/* ====================================================
   Auto-sync claims whenever Users/{uid}.Roles changes
   NOTE: preserves existing claims
==================================================== */
exports.syncRoleClaims = onDocumentWritten(
  { document: "Users/{uid}", region: "asia-southeast1" },
  async (event) => {
    try {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      if (!afterSnap?.exists) return;

      const before = beforeSnap?.data() || {};
      const after = afterSnap.data() || {};
      const uid = event.params.uid;

      const beforeRole = String(before.Roles || before.roles || "").trim().toLowerCase();
      let role = String(after.Roles || after.roles || "").trim().toLowerCase();

      // normalize
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
    } catch (e) {
      logger.error("syncRoleClaims FAILED", { error: String(e), stack: e?.stack });
    }
  }
);

/* ====================================================
   Delete subcollections helper (needed for Users/{uid})
==================================================== */
async function deleteSubcollection(db, parentRef, subName, batchSize = 250) {
  while (true) {
    const snap = await parentRef.collection(subName).limit(batchSize).get();
    if (snap.empty) return;

    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();

    if (snap.size < batchSize) return;
  }
}

/* ====================================================
   ADMIN-ONLY: Delete user (Auth + Firestore cleanup)
   - Deletes Users/{uid}
   - Deletes Users/{uid}/inventory + Users/{uid}/transaction
   - Deletes permitRequests
   - Deletes legacy Junkshop/{uid} if still present (safe during migration)
==================================================== */
exports.adminDeleteUser = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  if (!uid || typeof uid !== "string") throw new HttpsError("invalid-argument", "uid required");

  const db = admin.firestore();

  try {
    const userRef = db.collection("Users").doc(uid);

    // delete subcollections first
    await deleteSubcollection(db, userRef, "inventory");
    await deleteSubcollection(db, userRef, "transaction");

    // delete Users profile
    await userRef.delete().catch(() => null);

    // legacy cleanup (optional)
    await db.collection("Junkshop").doc(uid).delete().catch(() => null);

    // delete permit requests (docs)
    const permits = await db.collection("permitRequests").where("uid", "==", uid).get();
    const batch = db.batch();
    permits.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit().catch(() => null);

    // delete auth user
    await admin.auth().deleteUser(uid);

    return { ok: true, uid };
  } catch (err) {
    console.error("adminDeleteUser error:", err);
    throw new HttpsError("internal", err?.message || String(err));
  }
});

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
function normalizeText(v) {
  return String(v).trim();
}
function normalizeEmail(v) {
  return String(v).trim().toLowerCase();
}
function normalizeMoney(v) {
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
function encryptNormalizedToFields(normalized, AES_KEY, HMAC_KEY, fieldPrefix) {
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
  };
}

function encryptNormalizedToFieldsNoTimestamp(normalized, AES_KEY, HMAC_KEY, fieldPrefix) {
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
  };
}

function encryptStringToFields(plainText, AES_KEY, HMAC_KEY, fieldPrefix) {
  return encryptNormalizedToFields(normalizeText(plainText), AES_KEY, HMAC_KEY, fieldPrefix);
}
function encryptEmailToFields(email, AES_KEY, HMAC_KEY) {
  return encryptNormalizedToFields(normalizeEmail(email), AES_KEY, HMAC_KEY, "shopEmail");
}
function encryptMoneyToFields(value, AES_KEY, HMAC_KEY, fieldPrefix) {
  return encryptNormalizedToFields(normalizeMoney(value), AES_KEY, HMAC_KEY, fieldPrefix);
}
function encryptMoneyToFieldsForArray(value, AES_KEY, HMAC_KEY, fieldPrefix) {
  return encryptNormalizedToFieldsNoTimestamp(normalizeMoney(value), AES_KEY, HMAC_KEY, fieldPrefix);
}

/* ====================================================
   1) AUTO-ENCRYPT Users.email (only if Roles=junkshop)
==================================================== */
exports.encryptJunkshopEmailOnWrite = onDocumentWritten(
  {
    document: "Users/{uid}",
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data();
    const uid = event.params.uid;

    const role = String(after?.Roles || after?.roles || "").toLowerCase();
    if (role !== "junkshop") return;

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

      logger.info("Encrypted junkshop email on Users doc", { uid });
    } catch (err) {
      logger.error("Encryption failed (Users email)", { uid, message: err?.message, stack: err?.stack });
    }
  }
);

/* ====================================================
   2) AUTO-ENCRYPT Transaction customerName + total + items[].subtotal
   ✅ Keeps UI fields (avoid Walk-in + ₱0.00)
==================================================== */
exports.encryptTransactionCustomerOnWrite = onDocumentWritten(
  {
    document: "Users/{uid}/transaction/{txId}",
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data();
    const { uid, txId } = event.params;

    const hasTotalAmount = after?.totalAmount !== undefined && after?.totalAmount !== null;
    const hasTotalPrice = after?.totalPrice !== undefined && after?.totalPrice !== null;

    const updatePayload = {};

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();

      // customerName (PII)
      if (!after?.customerName_enc && after?.customerName != null) {
        if (typeof after.customerName === "string" && after.customerName.trim() !== "") {
          Object.assign(updatePayload, encryptStringToFields(after.customerName, AES_KEY, HMAC_KEY, "customerName"));

          // UI-safe display
          updatePayload.customerNameDisplay = after.customerName;

          // remove plaintext PII
          updatePayload.customerName = admin.firestore.FieldValue.delete();
        } else {
          logger.warn("Skipping customerName (not a non-empty string)", {
            uid,
            txId,
            type: typeof after.customerName,
          });
        }
      }

      // totalAmount (keep plaintext for UI)
      if (hasTotalAmount && !after?.totalAmount_enc) {
        Object.assign(updatePayload, encryptMoneyToFields(after.totalAmount, AES_KEY, HMAC_KEY, "totalAmount"));
      }

      // totalPrice (keep plaintext for UI)
      if (hasTotalPrice && !after?.totalPrice_enc) {
        Object.assign(updatePayload, encryptMoneyToFields(after.totalPrice, AES_KEY, HMAC_KEY, "totalPrice"));
      }

      // items[].subtotal (array-safe)
      if (Array.isArray(after.items) && after.items.length > 0) {
        const newItems = after.items.map((it) => {
          const copy = { ...(it || {}) };

          if (copy.subtotal != null && !copy.subtotal_enc) {
            Object.assign(copy, encryptMoneyToFieldsForArray(copy.subtotal, AES_KEY, HMAC_KEY, "subtotal"));
            copy.subtotalSetAtMs = Date.now(); // array-safe timestamp
          }
          return copy;
        });

        const itemsChanged = JSON.stringify(newItems) !== JSON.stringify(after.items);
        if (itemsChanged) updatePayload.items = newItems;
      }

      if (Object.keys(updatePayload).length === 0) return;

      await afterSnap.ref.update(updatePayload);
      logger.info("Encrypted transaction fields successfully", { uid, txId });
    } catch (err) {
      logger.error("Encryption failed (transaction)", {
        uid,
        txId,
        message: err?.message,
        stack: err?.stack,
      });
    }
  }
);

/* ====================================================
   ADMIN-ONLY: SET/ENCRYPT junkshop email into Users/{uid}
==================================================== */
exports.setJunkshopEmail = onCall(
  {
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be signed in.");
    if (request.auth.token?.admin !== true) throw new HttpsError("permission-denied", "Admin only.");

    const shopId = request.data?.shopId;
    const email = request.data?.email;

    if (!shopId || typeof shopId !== "string") throw new HttpsError("invalid-argument", "shopId is required.");
    if (!email || typeof email !== "string") throw new HttpsError("invalid-argument", "email is required.");

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();
      const encFields = encryptEmailToFields(email, AES_KEY, HMAC_KEY);

      const ref = admin.firestore().collection("Users").doc(shopId);

      await ref.set(
        {
          Roles: "junkshop", // optional, helpful for admin-set
          ...encFields,
          email: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );

      return { ok: true };
    } catch (err) {
      throw new HttpsError("internal", String(err));
    }
  }
);

/* ====================================================
   Helper — subtract days
==================================================== */
function daysAgo(days) {
  const ms = days * 24 * 60 * 60 * 1000;
  return admin.firestore.Timestamp.fromDate(new Date(Date.now() - ms));
}

/* ====================================================
   AUTO add approvedAt when admin approves permit
==================================================== */
exports.setApprovedAtOnApprove = onDocumentUpdated(
  {
    document: "permitRequests/{requestId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    if (before.approved !== true && after.approved === true) {
      v2_1.logger.info("Approved -> notify user", { requestId: event.params.requestId });

      // 1) set approvedAt once
      if (!after.approvedAt) {
        await afterSnap.ref.update({
          approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 2) send push notification
      const uid = after.uid; // you already use "uid" in adminDeleteUser permit query
      if (uid) {
        await sendPushToUser(
          uid,
          "Application Approved ✅",
          "Your application has been approved by the admin.",
          { type: "application_approved", requestId: event.params.requestId }
        );
      }
    }
  }
);

/* ====================================================
   SHARED CLEANUP LOGIC (batch update + safe file delete)
   - Unapproved older than 30 days -> mark expired + delete permit file
   - Approved older than 15 days -> mark expired + delete permit file
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

  logger.info("Permits eligible", {
    total: docsToDelete.length,
    unapproved: unapprovedSnap.size,
    approved: approvedSnap.size,
  });

  // delete files sequentially (safe) + batch update docs
  const batch = db.batch();
  let deleted = 0;

  for (const doc of docsToDelete) {
    const data = doc.data();
    const permitPath = data.permitPath;

    try {
      if (permitPath) {
        await bucket.file(permitPath).delete({ ignoreNotFound: true });
      }

      batch.update(doc.ref, {
        permitExpired: true,
        permitDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      deleted++;
      logger.info("Permit file removed", { requestId: doc.id, permitPath });
    } catch (err) {
      logger.error("Permit deletion failed", { requestId: doc.id, err: String(err) });
    }
  }

  await batch.commit().catch((e) => logger.error("Permit batch update failed", { err: String(e) }));

  logger.info("Cleanup finished", { deleted });
  return { deleted };
}

/* ====================================================
   SCHEDULED CLEANUP (Runs every 24h)
==================================================== */
exports.cleanupPermitsByRetention = onSchedule(
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
exports.runPermitCleanupNow = onRequest({ region: "asia-southeast1" }, async (req, res) => {
  try {
    const result = await cleanupPermits();
    res.status(200).json({ ok: true, ...result });
  } catch (err) {
    logger.error("Manual cleanup crashed", { err: String(err) });
    res.status(500).json({ ok: false, error: String(err) });
  }
});

/* ====================================================
   INVENTORY DEDUCTION (UNCHANGED logic, updated path)
==================================================== */
exports.deductInventoryOnTransactionCreate = onDocumentCreated(
  {
    document: "Users/{uid}/transaction/{txId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const { uid } = event.params;
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data || !Array.isArray(data.items)) return;

    const db = admin.firestore();

    await db.runTransaction(async (t) => {
      for (const item of data.items) {
        const inventoryRef = db
          .collection("Users")
          .doc(uid)
          .collection("inventory")
          .doc(item.inventoryDocId);

        const inventorySnap = await t.get(inventoryRef);
        if (!inventorySnap.exists) continue;

        const currentKg = Number(inventorySnap.data().unitsKg) || 0;
        const newKg = Math.max(currentKg - Number(item.weightKg), 0);

        t.update(inventoryRef, {
          unitsKg: newKg,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      t.update(snap.ref, {
        inventoryDeducted: true,
        inventoryDeductedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
);