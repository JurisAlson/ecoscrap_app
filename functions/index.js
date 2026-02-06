const admin = require("firebase-admin");
const { logger } = require("firebase-functions/v2");

const crypto = require("crypto");
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

admin.initializeApp();

/* ====================================================
   PII HELPERS (AES-256-GCM + HMAC lookup)
==================================================== */
function getKeysOrThrow() {
  const aesKeyB64 = process.env.PII_AES_KEY_B64;
  const hmacKeyB64 = process.env.PII_HMAC_KEY_B64;

  if (!aesKeyB64 || !hmacKeyB64) {
    throw new Error("Missing encryption secrets (PII_AES_KEY_B64 / PII_HMAC_KEY_B64).");
  }

  const AES_KEY = Buffer.from(aesKeyB64, "base64");
  const HMAC_KEY = Buffer.from(hmacKeyB64, "base64");

  if (AES_KEY.length !== 32) {
    throw new Error("AES key must be 32 bytes (AES-256).");
  }
  if (HMAC_KEY.length < 32) {
    throw new Error("HMAC key too short (recommend >= 32 bytes).");
  }

  return { AES_KEY, HMAC_KEY };
}

function normalizeEmail(email) {
  return String(email).trim().toLowerCase();
}

function encryptEmailToFields(email, AES_KEY, HMAC_KEY) {
  const normalized = normalizeEmail(email);

  const nonce = crypto.randomBytes(12); // 12 bytes for GCM
  const cipher = crypto.createCipheriv("aes-256-gcm", AES_KEY, nonce);

  const ciphertext = Buffer.concat([cipher.update(normalized, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  const lookup = crypto.createHmac("sha256", HMAC_KEY).update(normalized).digest("hex");

  return {
    shopEmail_enc: ciphertext.toString("base64"),
    shopEmail_nonce: nonce.toString("base64"),
    shopEmail_tag: tag.toString("base64"),
    shopEmail_lookup: lookup,
    piiVersion: 1,
    shopEmailSetAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/* ====================================================
   AUTO-ENCRYPT Junkshop.email ON CREATE/UPDATE
   - If plaintext `email` exists and not yet encrypted:
     write encrypted fields + delete plaintext `email`
==================================================== */
exports.encryptJunkshopEmailOnWrite = onDocumentWritten(
  {
    document: "Junkshop/{shopId}",
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data();
    const shopId = event.params.shopId;

    // Debug visibility (SAFE + useful)
    logger.info("Encrypt trigger fired", {
      shopId,
      hasEmail: !!after?.email,
      alreadyEncrypted: !!after?.shopEmail_enc,
    });

    // Only continue if plaintext email exists
    if (!after.email || typeof after.email !== "string") return;

    // Prevent infinite loop
    if (after.shopEmail_enc) return;

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();

      const encFields = encryptEmailToFields(
        after.email,
        AES_KEY,
        HMAC_KEY
      );

      await afterSnap.ref.update({
        ...encFields,
        email: admin.firestore.FieldValue.delete(),
      });

      logger.info("Encrypted junkshop email successfully", { shopId });

    } catch (err) {
      logger.error("Encryption failed", {
        shopId,
        error: String(err),
      });
    }
  }
);

/* ====================================================
   ADMIN-ONLY: SET/ENCRYPT Junkshop email via callable
   (Optional if you already auto-encrypt on write)
==================================================== */
exports.setJunkshopEmail = onCall(
  {
    region: "asia-southeast1",
    secrets: ["PII_AES_KEY_B64", "PII_HMAC_KEY_B64"],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    if (request.auth.token?.admin !== true) {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    const shopId = request.data?.shopId;
    const email = request.data?.email;

    if (!shopId || typeof shopId !== "string") {
      throw new HttpsError("invalid-argument", "shopId is required.");
    }
    if (!email || typeof email !== "string") {
      throw new HttpsError("invalid-argument", "email is required.");
    }

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();
      const encFields = encryptEmailToFields(email, AES_KEY, HMAC_KEY);

      const ref = admin.firestore().collection("Junkshop").doc(shopId);
      await ref.set(
        {
          ...encFields,
          email: admin.firestore.FieldValue.delete(), // ensure plaintext removed
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

    if (before.approved !== true && after.approved === true && !after.approvedAt) {
      logger.info("Auto setting approvedAt", { requestId: event.params.requestId });

      await event.data.after.ref.update({
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
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
    const data = doc.data();
    const permitPath = data.permitPath;

    try {
      if (permitPath) {
        await bucket.file(permitPath).delete({ ignoreNotFound: true });
      }

      await doc.ref.update({
        permitExpired: true,
        permitDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      deleted++;

      logger.info("Permit file removed", { requestId: doc.id, permitPath });
    } catch (err) {
      logger.error("Permit deletion failed", { requestId: doc.id, err: String(err) });
    }
  }

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
exports.runPermitCleanupNow = onRequest(
  { region: "asia-southeast1" },
  async (req, res) => {
    try {
      const result = await cleanupPermits();
      res.status(200).json({ ok: true, ...result });
    } catch (err) {
      logger.error("Manual cleanup crashed", { err: String(err) });
      res.status(500).json({ ok: false, error: String(err) });
    }
  }
);

/* ====================================================
   EXISTING INVENTORY FUNCTION (UNCHANGED)
==================================================== */
exports.deductInventoryOnTransactionCreate = onDocumentCreated(
  {
    document: "Junkshop/{shopId}/transaction/{txId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const { shopId } = event.params;
    const snap = event.data;

    if (!snap) return;

    const data = snap.data();
    if (!data || !Array.isArray(data.items)) return;

    const db = admin.firestore();

    await db.runTransaction(async (t) => {
      for (const item of data.items) {
        const inventoryRef = db
          .collection("Junkshop")
          .doc(shopId)
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
