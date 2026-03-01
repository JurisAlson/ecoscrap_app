// functions/src/index.ts

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

/* ====================================================
  PUSH HELPERS
==================================================== */

async function getAdminUids(): Promise<string[]> {
  const db = admin.firestore();

  const snapA = await db
    .collection("Users")
    .where("Roles", "in", ["admin", "admins", "Admin", "Admins"])
    .get();

  const snapB = await db
    .collection("Users")
    .where("role", "in", ["admin", "admins", "Admin", "Admins"])
    .get();

  const set = new Set<string>();
  snapA.docs.forEach((d) => set.add(d.id));
  snapB.docs.forEach((d) => set.add(d.id));

  return [...set];
}

async function sendPushToMany(
  uids: string[],
  title: string,
  body: string,
  data: Record<string, any> = {}
) {
  await Promise.allSettled(
    uids.map((uid) => sendPushToUser(uid, title, body, data))
  );
}

async function createInAppNotification(
  uid: string,
  title: string,
  body: string,
  data: Record<string, any> = {}
) {
  await admin
    .firestore()
    .collection("Users")
    .doc(uid)
    .collection("notifications")
    .add({
      title,
      body,
      type: String(data.type || ""),
      data,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function sendPushToUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, any> = {}
) {
  // Always create in-app notification
  await createInAppNotification(uid, title, body, data);

  const userRef = admin.firestore().collection("Users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    logger.warn("sendPushToUser: no Users doc", { uid });
    return;
  }

  const u = userSnap.data() as any;

  const token =
    u?.fcmToken ||
    u?.fcm_token ||
    u?.deviceToken ||
    (Array.isArray(u?.fcmTokens) ? u.fcmTokens[0] : undefined);

  if (!token) {
    logger.warn("sendPushToUser: missing token fields", { uid, keys: Object.keys(u || {}) });
    return;
  }

  const stringData: Record<string, string> = Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, String(v)])
  );

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: stringData,
    });
    logger.info("sendPushToUser: sent", { uid });
  } catch (e: any) {
    logger.error("sendPushToUser: FCM send failed", {
      uid,
      code: e?.code,
      message: String(e?.message || e),
    });

    // auto-remove dead tokens so future sends don’t keep failing
    if (
      e?.code === "messaging/registration-token-not-registered" ||
      e?.code === "messaging/invalid-registration-token"
    ) {
      await userRef.set(
        { fcmToken: admin.firestore.FieldValue.delete() },
        { merge: true }
      );
      logger.warn("sendPushToUser: removed invalid fcmToken", { uid });
    }
  }
}

/* ====================================================
  ADMIN-ONLY: Reject resident
==================================================== */
export const adminRejectResident = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const uid = String(request.data?.uid || "").trim();
    const reason = String(request.data?.reason || "").trim();
    if (!uid) throw new HttpsError("invalid-argument", "uid required");

    await admin.firestore().collection("residentRequests").doc(uid).set(
      {
        status: "rejected",
        adminStatus: "rejected",
        adminVerified: false,
        adminReviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        rejectReason: reason,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { ok: true, uid };
  }
);

/* ====================================================
  SANITIZE residentRequests PII (remove publicName/emailDisplay)
==================================================== */
export const sanitizeResidentRequestPII = onDocumentWritten(
  { document: "residentRequests/{uid}", region: "asia-southeast1" },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const beforeData = event.data?.before?.data() as any | undefined;
    const afterData = after.data() as any;

    const hasPII =
      afterData?.emailDisplay != null || afterData?.publicName != null;
    if (!hasPII) return;

    const alreadySanitized =
      beforeData != null &&
      beforeData?.emailDisplay == null &&
      beforeData?.publicName == null;

    if (alreadySanitized) return;

    await after.ref.update({
      emailDisplay: admin.firestore.FieldValue.delete(),
      publicName: admin.firestore.FieldValue.delete(),
    });

    logger.info("residentRequests sanitized (PII removed)", {
      uid: event.params.uid,
    });
  }
);

/* ====================================================
  ADMIN-ONLY: Set user role in Firestore (routing)
==================================================== */
export const setUserRole = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const uid = request.data?.uid as string | undefined;
    let role = String(request.data?.role || "").trim().toLowerCase();

    if (role === "users") role = "user";
    if (role === "admins") role = "admin";
    if (role === "collectors") role = "collector";
    if (role === "junkshops") role = "junkshop";

    const allowed = ["user", "collector", "junkshop", "admin"];
    if (!uid || typeof uid !== "string")
      throw new HttpsError("invalid-argument", "uid required");
    if (!allowed.includes(role))
      throw new HttpsError("invalid-argument", "Invalid role");

    await admin
      .firestore()
      .collection("Users")
      .doc(uid)
      .set({ Roles: role }, { merge: true });

    return { ok: true, uid, role };
  }
);

/* ====================================================
  ADMIN-ONLY: Verify junkshop
==================================================== */
export const verifyJunkshop = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const uid = request.data?.uid as string | undefined;
    if (!uid || typeof uid !== "string")
      throw new HttpsError("invalid-argument", "uid required");

    await admin
      .firestore()
      .collection("Junkshop")
      .doc(uid)
      .set(
        {
          verified: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    await admin
      .firestore()
      .collection("Users")
      .doc(uid)
      .set({ Roles: "junkshop" }, { merge: true });

    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};

    await admin.auth().setCustomUserClaims(uid, {
      ...existing,
      junkshop: true,
      collector: false,
      admin: existing.admin === true,
    });

    return { ok: true, uid };
  }
);

/* ====================================================
  ADMIN-ONLY: Delete user (Auth + Firestore cleanup)
==================================================== */
export const adminDeleteUser = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const uid = request.data?.uid as string | undefined;
    if (!uid || typeof uid !== "string")
      throw new HttpsError("invalid-argument", "uid required");

    const db = admin.firestore();

    try {
      await db.collection("Users").doc(uid).delete().catch(() => null);
      await db.collection("Junkshop").doc(uid).delete().catch(() => null);

      const permits = await db
        .collection("permitRequests")
        .where("uid", "==", uid)
        .get();

      const batch = db.batch();
      permits.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit().catch(() => null);

      await admin.auth().deleteUser(uid);
      return { ok: true, uid };
    } catch (err: any) {
      logger.error("adminDeleteUser error", {
        err: String(err),
        stack: err?.stack,
      });
      throw new HttpsError("internal", err?.message || String(err));
    }
  }
);

/* ====================================================
  Revert collector on rejection
==================================================== */
export const revertCollectorOnRejected = onDocumentUpdated(
  { document: "collectorRequests/{collectorUid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    if (!before || !after) return;

    const uid = String(event.params.collectorUid);

    const b = String(before.status || before.adminStatus || "").toLowerCase();
    const a = String(after.status || after.adminStatus || "").toLowerCase();
    if (a === b) return;

    if (a !== "rejected") return;

    const db = admin.firestore();

    // reset collector claim
    try {
      const user = await admin.auth().getUser(uid);
      const existing = user.customClaims || {};
      await admin.auth().setCustomUserClaims(uid, {
        ...existing,
        collector: false,
      });
    } catch (e) {
      logger.warn("Failed to reset collector claim", { uid, err: String(e) });
    }

    // revert role if it was collector
    const userRef = db.collection("Users").doc(uid);
    const userSnap = await userRef.get();
    const u = (userSnap.data() || {}) as any;

    const currentRole = String(u.Roles || u.role || "").toLowerCase();
    if (currentRole === "collector") {
      await userRef.set(
        {
          Roles: "user",
          role: "user",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // cleanup KYC doc
    await db.collection("collectorKYC").doc(uid).delete().catch(() => null);

    // archive request (keeps doc but removes PII)
    await event.data!.after.ref.set(
      {
        archived: true,
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        emailDisplay: admin.firestore.FieldValue.delete(),
        publicName: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );

    logger.info("Collector rejected: reverted + cleared for resubmit", { uid });
  }
);

/* ====================================================
  Revert resident on rejection
==================================================== */
export const revertResidentOnRejected = onDocumentUpdated(
  { document: "residentRequests/{uid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    if (!before || !after) return;

    const uid = String(event.params.uid);

    const b = String(before.status || before.adminStatus || "").toLowerCase();
    const a = String(after.status || after.adminStatus || "").toLowerCase();
    if (a === b) return;
    if (a !== "rejected") return;

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    // delete residentKYC file + doc
    try {
      const kycSnap = await db.collection("residentKYC").doc(uid).get();
      const kyc = (kycSnap.data() || {}) as any;
      const storagePath = String(kyc.storagePath || "").trim();
      if (storagePath) {
        await bucket.file(storagePath).delete({ ignoreNotFound: true } as any);
      }
    } catch (e) {
      logger.warn("residentKYC cleanup failed", { uid, err: String(e) });
    }

    await db.collection("residentKYC").doc(uid).delete().catch(() => null);

    const userRef = db.collection("Users").doc(uid);
    const userSnap = await userRef.get();
    const u = (userSnap.data() || {}) as any;

    const currentRole = String(u.Roles || u.role || "").toLowerCase();

    if (currentRole === "resident") {
      await userRef.set(
        {
          Roles: "user",
          role: "user",
          residentStatus: "rejected",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      await userRef.set(
        {
          residentStatus: "rejected",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // allow resubmit
    await event.data!.after.ref.delete().catch(() => null);

    logger.info("Resident rejected: reverted + cleared for resubmit", { uid });
  }
);

/* ====================================================
  ADMIN-ONLY: Grant/Revoke admin claim
==================================================== */
export const setAdminClaim = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const uid = request.data?.uid as string | undefined;
    const makeAdmin = request.data?.makeAdmin as boolean | undefined;

    if (!uid || typeof uid !== "string")
      throw new HttpsError("invalid-argument", "uid required");
    if (typeof makeAdmin !== "boolean")
      throw new HttpsError("invalid-argument", "makeAdmin must be boolean");

    try {
      const user = await admin.auth().getUser(uid);
      const existing = user.customClaims || {};
      await admin.auth().setCustomUserClaims(uid, {
        ...existing,
        admin: makeAdmin,
      });
      return { ok: true, uid, admin: makeAdmin };
    } catch (err: any) {
      throw new HttpsError("internal", err?.message || String(err));
    }
  }
);

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

      const beforeRole = String(before.Roles || before.roles || "")
        .trim()
        .toLowerCase();
      let role = String(after.Roles || after.roles || "")
        .trim()
        .toLowerCase();

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
      await admin.auth().setCustomUserClaims(uid, {
        ...existing,
        ...roleClaims,
      });

      logger.info("RBAC Claims synced", { uid, role, roleClaims });
    } catch (e: any) {
      logger.error("syncRoleClaims FAILED", {
        error: String(e),
        stack: e?.stack,
      });
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
    throw new Error(
      "Missing encryption secrets (PII_AES_KEY_B64 / PII_HMAC_KEY_B64)."
    );
  }

  const AES_KEY = Buffer.from(aesKeyB64, "base64");
  const HMAC_KEY = Buffer.from(hmacKeyB64, "base64");

  if (AES_KEY.length !== 32)
    throw new Error("AES key must be 32 bytes (AES-256).");
  if (HMAC_KEY.length < 32)
    throw new Error("HMAC key too short (recommend >= 32 bytes).");

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
function encryptNormalizedToFields(
  normalized: string,
  AES_KEY: Buffer,
  HMAC_KEY: Buffer,
  fieldPrefix: string
) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", AES_KEY, nonce);

  const ciphertext = Buffer.concat([
    cipher.update(normalized, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  const lookup = crypto
    .createHmac("sha256", HMAC_KEY)
    .update(normalized)
    .digest("hex");

  return {
    [`${fieldPrefix}_enc`]: ciphertext.toString("base64"),
    [`${fieldPrefix}_nonce`]: nonce.toString("base64"),
    [`${fieldPrefix}_tag`]: tag.toString("base64"),
    [`${fieldPrefix}_lookup`]: lookup,
    piiVersion: 1,
    [`${fieldPrefix}SetAt`]: admin.firestore.FieldValue.serverTimestamp(),
  } as Record<string, any>;
}

function encryptNormalizedToFieldsNoTimestamp(
  normalized: string,
  AES_KEY: Buffer,
  HMAC_KEY: Buffer,
  fieldPrefix: string
) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", AES_KEY, nonce);

  const ciphertext = Buffer.concat([
    cipher.update(normalized, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  const lookup = crypto
    .createHmac("sha256", HMAC_KEY)
    .update(normalized)
    .digest("hex");

  return {
    [`${fieldPrefix}_enc`]: ciphertext.toString("base64"),
    [`${fieldPrefix}_nonce`]: nonce.toString("base64"),
    [`${fieldPrefix}_tag`]: tag.toString("base64"),
    [`${fieldPrefix}_lookup`]: lookup,
  } as Record<string, any>;
}

function encryptStringToFields(
  plainText: any,
  AES_KEY: Buffer,
  HMAC_KEY: Buffer,
  fieldPrefix: string
) {
  return encryptNormalizedToFields(
    normalizeText(plainText),
    AES_KEY,
    HMAC_KEY,
    fieldPrefix
  );
}

function encryptEmailToFields(email: any, AES_KEY: Buffer, HMAC_KEY: Buffer) {
  return encryptNormalizedToFields(
    normalizeEmail(email),
    AES_KEY,
    HMAC_KEY,
    "shopEmail"
  );
}

function encryptMoneyToFields(
  value: any,
  AES_KEY: Buffer,
  HMAC_KEY: Buffer,
  fieldPrefix: string
) {
  return encryptNormalizedToFields(
    normalizeMoney(value),
    AES_KEY,
    HMAC_KEY,
    fieldPrefix
  );
}

function encryptMoneyToFieldsForArray(
  value: any,
  AES_KEY: Buffer,
  HMAC_KEY: Buffer,
  fieldPrefix: string
) {
  return encryptNormalizedToFieldsNoTimestamp(
    normalizeMoney(value),
    AES_KEY,
    HMAC_KEY,
    fieldPrefix
  );
}

/* ====================================================
  1) AUTO-ENCRYPT Junkshop.email ON WRITE
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

    const hasPlainEmail =
      typeof after?.email === "string" && after.email.trim() !== "";
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
      logger.error("Encryption failed (Junkshop email)", {
        shopId,
        message: err?.message,
        stack: err?.stack,
      });
    }
  }
);

/* ====================================================
  2) AUTO-ENCRYPT Transaction fields
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

      if (!after?.customerName_enc && after?.customerName != null) {
        if (
          typeof after.customerName === "string" &&
          after.customerName.trim() !== ""
        ) {
          Object.assign(
            updatePayload,
            encryptStringToFields(after.customerName, AES_KEY, HMAC_KEY, "customerName")
          );
          updatePayload.customerNameDisplay = after.customerName;
          updatePayload.customerName = admin.firestore.FieldValue.delete();
        }
      }

      if (
        after?.totalAmount !== undefined &&
        after?.totalAmount !== null &&
        !after?.totalAmount_enc
      ) {
        Object.assign(
          updatePayload,
          encryptMoneyToFields(after.totalAmount, AES_KEY, HMAC_KEY, "totalAmount")
        );
      }

      if (
        after?.totalPrice !== undefined &&
        after?.totalPrice !== null &&
        !after?.totalPrice_enc
      ) {
        Object.assign(
          updatePayload,
          encryptMoneyToFields(after.totalPrice, AES_KEY, HMAC_KEY, "totalPrice")
        );
      }

      if (Array.isArray(after.items) && after.items.length > 0) {
        const newItems = after.items.map((it: any) => {
          const copy = { ...(it || {}) };
          if (copy.subtotal != null && !copy.subtotal_enc) {
            Object.assign(
              copy,
              encryptMoneyToFieldsForArray(copy.subtotal, AES_KEY, HMAC_KEY, "subtotal")
            );
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
      logger.error("Encryption failed (transaction)", {
        shopId,
        txId,
        message: err?.message,
        stack: err?.stack,
      });
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
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Must be signed in.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const shopId = request.data?.shopId as string | undefined;
    const email = request.data?.email as string | undefined;

    if (!shopId || typeof shopId !== "string")
      throw new HttpsError("invalid-argument", "shopId is required.");
    if (!email || typeof email !== "string")
      throw new HttpsError("invalid-argument", "email is required.");

    try {
      const { AES_KEY, HMAC_KEY } = getKeysOrThrow();
      const encFields = encryptEmailToFields(email, AES_KEY, HMAC_KEY);

      const ref = admin.firestore().collection("Junkshop").doc(shopId);
      await ref.set(
        { ...encFields, email: admin.firestore.FieldValue.delete() },
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
  AUTO approvedAt + notify user when admin approves/rejects permit
==================================================== */
export const setApprovedAtOnApprove = onDocumentUpdated(
  { document: "permitRequests/{requestId}", region: "asia-southeast1" },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap || !afterSnap) return;

    const before = beforeSnap.data() as any;
    const after = afterSnap.data() as any;
    if (!before || !after) return;

    const uid = String(after.uid || "").trim();
    if (!uid) return;

    const beforeApproved = before.approved === true;
    const afterApproved = after.approved === true;
    const afterStatus = String(after.status || "").trim().toLowerCase();

    if (!beforeApproved && afterApproved) {
      if (!after.approvedAt) {
        await afterSnap.ref.update({
          approvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      await sendPushToUser(
        uid,
        "Junkshop Application Approved ✅",
        "Your junkshop application has been approved by the admin.",
        { type: "junkshop_approved", requestId: String(event.params.requestId) }
      );
      return;
    }

    if (afterApproved === false && afterStatus === "rejected") {
      const beforeStatus = String(before.status || "").trim().toLowerCase();
      if (beforeStatus === "rejected") return;

      await sendPushToUser(
        uid,
        "Junkshop Application Rejected ❌",
        "Your junkshop application was rejected by the admin.",
        { type: "junkshop_rejected", requestId: String(event.params.requestId) }
      );

      logger.info("Junkshop rejection notified", {
        uid,
        requestId: event.params.requestId,
      });
      return;
    }
  }
);

/* ====================================================
  RESIDENT KYC CLEANUP (scheduled)
==================================================== */
async function cleanupResidentKyc() {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const cutoffPending = daysAgo(30);
  const cutoffApproved = daysAgo(15);

  logger.info("Starting residentKYC cleanup", {
    cutoffPending: cutoffPending.toDate().toISOString(),
    cutoffApproved: cutoffApproved.toDate().toISOString(),
  });

  let deleted = 0;

  const snap = await db.collection("residentKYC").limit(500).get();

  for (const doc of snap.docs) {
    const data = doc.data() as any;
    const uid = doc.id;

    const status = String(data.status || "").toLowerCase();
    const createdAt = data.createdAt;
    const approvedAt = data.approvedAt;
    const storagePath = String(data.storagePath || "").trim();

    try {
      if (status === "rejected") {
        if (storagePath) {
          await bucket.file(storagePath).delete({ ignoreNotFound: true } as any);
        }
        await doc.ref.delete();
        deleted++;
        continue;
      }

      if (
        status === "pending" &&
        createdAt &&
        createdAt.toMillis() <= cutoffPending.toMillis()
      ) {
        if (storagePath) {
          await bucket.file(storagePath).delete({ ignoreNotFound: true } as any);
        }
        await doc.ref.delete();
        deleted++;
        continue;
      }

      if (
        status === "approved" &&
        approvedAt &&
        approvedAt.toMillis() <= cutoffApproved.toMillis() &&
        !data.kycExpired
      ) {
        if (storagePath) {
          await bucket.file(storagePath).delete({ ignoreNotFound: true } as any);
        }
        await doc.ref.update({
          kycExpired: true,
          kycDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        deleted++;
      }
    } catch (err: any) {
      logger.error("residentKYC cleanup failed", { uid, error: String(err) });
    }
  }

  logger.info("residentKYC cleanup finished", { deleted });
  return { deleted };
}

export const cleanupResidentKycByRetention = onSchedule(
  {
    schedule: "every 24 hours",
    region: "asia-southeast1",
    timeZone: "Asia/Manila",
  },
  async () => {
    const result = await cleanupResidentKyc();
    logger.info("Scheduled residentKYC cleanup result", result);
  }
);

export const runResidentKycCleanupNow = onRequest(
  { region: "asia-southeast1" },
  async (req, res) => {
    try {
      const result = await cleanupResidentKyc();
      res.status(200).json({ ok: true, ...result });
    } catch (err: any) {
      res.status(500).json({ ok: false, error: String(err) });
    }
  }
);

/* ====================================================
  INVENTORY DEDUCTION (sale) + ADD (buy)
==================================================== */
export const deductInventoryOnTransactionCreate = onDocumentCreated(
  { document: "Junkshop/{shopId}/transaction/{txId}", region: "asia-southeast1" },
  async (event) => {
    const { shopId } = event.params;
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    if (!data || !Array.isArray(data.items)) return;

    const txType = String(data.transactionType || "sale").toLowerCase();
    if (txType !== "sale") return;

    if (data.inventoryDeducted === true) return;

    const db = admin.firestore();
    const EPS = 0.0001;
    const round2 = (n: number) => Math.round(n * 100) / 100;

    await db.runTransaction(async (t) => {
      for (const item of data.items) {
        const invId = String(item.inventoryDocId || "").trim();
        if (!invId) continue;

        const weight = Number(item.weightKg);
        if (!Number.isFinite(weight) || weight <= 0) continue;

        const inventoryRef = db
          .collection("Junkshop")
          .doc(shopId)
          .collection("inventory")
          .doc(invId);

        const inventorySnap = await t.get(inventoryRef);
        if (!inventorySnap.exists) continue;

        const rawCurrent = Number((inventorySnap.data() as any).unitsKg);
        const currentKg = Number.isFinite(rawCurrent) ? rawCurrent : 0;

        let newKg = round2(currentKg - weight);
        if (newKg < 0 && Math.abs(newKg) <= EPS) newKg = 0;
        if (newKg < 0) {
          logger.warn("Oversell detected (clamping to 0)", {
            shopId,
            invId,
            currentKg,
            weight,
            newKg,
          });
          newKg = 0;
        }

        if (newKg === 0) t.delete(inventoryRef);
        else
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

export const addInventoryOnBuyCreate = onDocumentCreated(
  { document: "Junkshop/{shopId}/transaction/{txId}", region: "asia-southeast1" },
  async (event) => {
    const { shopId } = event.params;
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    if (!data || !Array.isArray(data.items)) return;

    const txType = String(data.transactionType || "sale").toLowerCase();
    if (txType !== "buy") return;

    if (data.inventoryAdded === true) return;

    const db = admin.firestore();

    await db.runTransaction(async (t) => {
      for (const item of data.items) {
        const weightKg = Number(item.weightKg) || 0;
        if (weightKg <= 0) continue;

        const category = String(item.category || "").trim();
        const subCategory = String(item.subCategory || "").trim();
        if (!category || !subCategory) continue;

        const invQuery = db
          .collection("Junkshop")
          .doc(shopId)
          .collection("inventory")
          .where("category", "==", category)
          .where("subCategory", "==", subCategory)
          .limit(1);

        const qSnap = await t.get(invQuery);

        if (!qSnap.empty) {
          const invDoc = qSnap.docs[0];
          const currentKg = Number((invDoc.data() as any).unitsKg) || 0;
          const newKg = currentKg + weightKg;

          t.update(invDoc.ref, {
            unitsKg: newKg,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          const invRef = db
            .collection("Junkshop")
            .doc(shopId)
            .collection("inventory")
            .doc();

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

      t.update(snap.ref, {
        inventoryAdded: true,
        inventoryAddedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
);

/* ====================================================
  ADMIN NOTIFIED: junkshop apply
==================================================== */
export const notifyAdminOnJunkshopApply = onDocumentCreated(
  { document: "permitRequests/{requestId}", region: "asia-southeast1" },
  async (event) => {
    const after = event.data?.data() as any;
    if (!after) return;

    const requestId = String(event.params.requestId);
    const uid = String(after.uid || "").trim();
    if (!uid) return;

    const admins = await getAdminUids();
    if (admins.length === 0) return;

    await sendPushToMany(
      admins,
      "New Junkshop Application 🏪",
      "A new junkshop permit request was submitted.",
      { type: "admin_new_junkshop_request", uid, requestId }
    );

    logger.info("Admins notified of junkshop application", {
      uid,
      requestId,
      adminCount: admins.length,
    });
  }
);

/* ====================================================
  ADMIN NOTIFIED: collector apply (pending)
==================================================== */
export const notifyAdminOnCollectorApply = onDocumentWritten(
  { document: "collectorRequests/{collectorUid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    if (!after) return;

    const uid = String(event.params.collectorUid);

    const b = String(before?.status || "").trim().toLowerCase();
    const a = String(after?.status || "").trim().toLowerCase();

    // Only when becomes pending (new or resubmitted)
    if (a !== "pending" || a === b) return;

    const name = String(after.publicName || "Collector");
    const email = String(after.emailDisplay || "");

    const admins = await getAdminUids();
    logger.info("notifyAdminOnCollectorApply", { uid, a, b, adminCount: admins.length });

    if (admins.length === 0) return;

    await sendPushToMany(
      admins,
      "New Collector Application 📩",
      `${name}${email ? ` (${email})` : ""} submitted a collector request.`,
      { type: "admin_new_collector_request", collectorUid: uid }
    );
  }
);

/* ====================================================
  ADMIN NOTIFIED: resident apply (pending)
==================================================== */
export const notifyAdminOnResidentApply = onDocumentWritten(
  { document: "residentRequests/{uid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any | undefined;
    const after = event.data?.after?.data() as any | undefined;
    if (!after) return;

    const uid = String(event.params.uid);

    const b = String(before?.status || "").trim().toLowerCase();
    const a = String(after?.status || "").trim().toLowerCase();

    if (a !== "pending" || a === b) return;

    const name = String(after.publicName || "Resident");
    const email = String(after.emailDisplay || "");

    const admins = await getAdminUids();
    logger.info("notifyAdminOnResidentApply", { uid, a, b, adminCount: admins.length });
    if (admins.length === 0) return;

    await sendPushToMany(
      admins,
      "New Resident Request 🏠",
      `${name}${email ? ` (${email})` : ""} submitted a resident verification request.`,
      { type: "admin_new_resident_request", residentUid: uid }
    );
  }
);

/* ====================================================
  PICKUP: Notify junkshop when pickup becomes CONFIRMED
==================================================== */
export const notifyJunkshopOnPickupConfirmed = onDocumentUpdated(
  { document: "requests/{requestId}", region: "asia-southeast1" },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    if (!beforeSnap || !afterSnap) return;

    const before = (beforeSnap.data() || {}) as any;
    const after = (afterSnap.data() || {}) as any;

    if (String(after.type || "").toLowerCase() !== "pickup") return;

    const beforeStatus = String(before.status || "").toLowerCase();
    const afterStatus = String(after.status || "").toLowerCase();

    if (beforeStatus === afterStatus) return;
    if (afterStatus !== "confirmed") return;

    let junkshopId = String(after.junkshopId || "").trim();

    // fallback: derive from collector Users doc
    if (!junkshopId) {
      const collectorId = String(after.collectorId || "").trim();
      if (collectorId) {
        const collectorSnap = await admin
          .firestore()
          .collection("Users")
          .doc(collectorId)
          .get();
        if (collectorSnap.exists) {
          const c = collectorSnap.data() as any;
          junkshopId = String(c.assignedJunkshopUid || c.junkshopId || "").trim();
        }
      }
    }

    if (!junkshopId) {
      logger.warn("No junkshopId found for confirmed pickup", {
        requestId: event.params.requestId,
      });
      return;
    }

    const requestId = String(event.params.requestId);

    await sendPushToUser(
      junkshopId,
      "Pickup confirmed ✅",
      "A pickup was confirmed by the collector and the household.",
      { type: "pickup_confirmed", requestId }
    );

    logger.info("Junkshop notified for confirmed pickup", {
      requestId,
      junkshopId,
    });
  }
);

/* ====================================================
  RESIDENT: notify on admin reject
  (supports status OR adminStatus)
==================================================== */
export const notifyResidentAdminRejected = onDocumentUpdated(
  { document: "residentRequests/{uid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    if (!before || !after) return;

    const uid = String(after?.uid || event.params.uid || "").trim();
    if (!uid) return;

    const b = String(before.status || before.adminStatus || "").trim().toLowerCase();
    const a = String(after.status || after.adminStatus || "").trim().toLowerCase();
    if (a === b) return;

    if (a !== "rejected") return;

    const reason = String(after.rejectReason || after.adminRejectReason || "").trim();

    await sendPushToUser(
      uid,
      "Resident verification rejected ❌",
      reason.length > 0
        ? `Your residency request was rejected. Reason: ${reason}`
        : "Your residency request was rejected by the admin.",
      { type: "resident_admin_rejected" }
    );

    logger.info("Resident rejected notification sent", { uid });
  }
);

/* ====================================================
  COLLECTOR: notify on admin approve/reject
  (supports status OR adminStatus)
==================================================== */
export const notifyCollectorAdminDecision = onDocumentUpdated(
  { document: "collectorRequests/{collectorUid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    if (!before || !after) return;

    const uid = String(after?.uid || event.params.collectorUid || "").trim();
    if (!uid) return;

    const b = String(before.status || before.adminStatus || "").trim().toLowerCase();
    const a = String(after.status || after.adminStatus || "").trim().toLowerCase();
    if (a === b) return;

    // approved
    if (a === "adminapproved" || a === "approved") {
      await sendPushToUser(
        uid,
        "Collector approved ✅",
        "Your collector application has been approved by the admin.",
        { type: "collector_admin_approved" }
      );
      logger.info("Collector approved notification sent", { uid });
      return;
    }

    // rejected
    if (a === "rejected") {
      const reason = String(after.adminRejectReason || after.rejectReason || "").trim();

      await sendPushToUser(
        uid,
        "Collector rejected ❌",
        reason.length > 0
          ? `Your collector application was rejected. Reason: ${reason}`
          : "Your collector application was rejected by the admin.",
        { type: "collector_admin_rejected" }
      );
      logger.info("Collector rejected notification sent", { uid });
      return;
    }
  }
);

/* ====================================================
  RESIDENT: notify on admin approved
  (supports status OR adminStatus)
==================================================== */
export const notifyResidentAdminApproved = onDocumentUpdated(
  { document: "residentRequests/{uid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() as any;
    const after = event.data?.after?.data() as any;
    if (!before || !after) return;

    const uid = String(after?.uid || event.params.uid || "").trim();
    if (!uid) return;

    const b = String(before.status || before.adminStatus || "").trim().toLowerCase();
    const a = String(after.status || after.adminStatus || "").trim().toLowerCase();
    if (a === b) return;

    if (a !== "adminapproved" && a !== "approved") return;

    await sendPushToUser(
      uid,
      "Resident approved ✅",
      "Your residency request has been approved.",
      { type: "resident_admin_approved" }
    );
  }
);

/* ====================================================
  RESTRICT ACCOUNT (admin)
==================================================== */
export const adminSetUserRestricted = onCall(
  { region: "asia-southeast1" },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Login required.");
    if (request.auth.token?.admin !== true)
      throw new HttpsError("permission-denied", "Admin only.");

    const uid = String(request.data?.uid || "").trim();
    const restricted = Boolean(request.data?.restricted);

    if (!uid) throw new HttpsError("invalid-argument", "uid required");

    if (request.auth.uid === uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot restrict your own admin account."
      );
    }

    await admin.auth().updateUser(uid, { disabled: restricted });
    await admin.auth().revokeRefreshTokens(uid);

    await admin.firestore().collection("Users").doc(uid).set(
      {
        status: restricted ? "restricted" : "active",
        restrictedAt: restricted
          ? admin.firestore.FieldValue.serverTimestamp()
          : null,
        unrestrictedAt: !restricted
          ? admin.firestore.FieldValue.serverTimestamp()
          : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    try {
      const user = await admin.auth().getUser(uid);
      const existing = user.customClaims || {};
      await admin.auth().setCustomUserClaims(uid, { ...existing, restricted });
    } catch (e) {
      logger.warn("Failed to set restricted claim", { uid, err: String(e) });
    }

    return { ok: true, uid, restricted };
  }
);