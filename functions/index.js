const admin = require("firebase-admin");
const { logger } = require("firebase-functions/v2");
const crypto = require("crypto");
const { defineSecret } = require("firebase-functions/params");
const GOOGLE_MAPS_API_KEY = defineSecret("GOOGLE_MAPS_API_KEY");
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
  if (request.auth.token?.admin !== true)
    throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  let role = String(request.data?.role || "").trim().toLowerCase();

  // normalize common variants
  if (role === "users") role = "user";
  if (role === "admins") role = "admin";
  if (role === "collectors") role = "collector";
  if (role === "junkshops") role = "junkshop";

  const allowed = ["user", "collector", "junkshop", "admin"];
  if (!uid || typeof uid !== "string")
    throw new HttpsError("invalid-argument", "uid required");
  if (!allowed.includes(role))
    throw new HttpsError("invalid-argument", "Invalid role");

  await admin.firestore().collection("Users").doc(uid).set({ Roles: role }, { merge: true });
  return { ok: true, uid, role };
});

/* ====================================================
   ADMIN-ONLY: Verify junkshop
==================================================== */
exports.verifyJunkshop = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true)
    throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  if (!uid || typeof uid !== "string")
    throw new HttpsError("invalid-argument", "uid required");

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

/* ====================================================
   ADMIN-ONLY: Review junkshop permit request
==================================================== */
exports.reviewPermitRequest = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true)
    throw new HttpsError("permission-denied", "Admin only.");

  const uid = String(request.data?.uid || "").trim();
  const decision = String(request.data?.decision || "").trim().toLowerCase(); // approved | rejected

  if (!uid) throw new HttpsError("invalid-argument", "uid required");
  if (!["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "decision must be approved|rejected");
  }

  const db = admin.firestore();
  const reqRef = db.collection("permitRequests").doc(uid);
  const userRef = db.collection("Users").doc(uid);

  const reviewedByUid = request.auth.uid;

  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new HttpsError("not-found", "permit request not found");

  const batch = db.batch();

  batch.set(
    reqRef,
    {
      status: decision,
      approved: decision === "approved",
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedByUid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(decision === "approved"
        ? { approvedAt: admin.firestore.FieldValue.serverTimestamp() }
        : {}),
    },
    { merge: true }
  );

  if (decision === "approved") {
    batch.set(
      userRef,
      {
        role: "junkshop",
        Roles: "junkshop",
        junkshopStatus: "approved",
        verified: true,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        activePermitRequestId: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } else {
    batch.set(
      userRef,
      {
        role: "user",
        Roles: "user",
        junkshopStatus: "rejected",
        activePermitRequestId: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  await batch.commit();

  if (decision === "approved") {
    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};
    await admin.auth().setCustomUserClaims(uid, {
      ...existing,
      junkshop: true,
      collector: false,
    });
  }

  return { ok: true, uid, decision };
});

/* ====================================================
   OWNER/ADMIN-ONLY: Grant/Revoke admin claim
==================================================== */
exports.setAdminClaim = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true)
    throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  const makeAdmin = request.data?.makeAdmin;

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
==================================================== */
exports.adminDeleteUser = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  if (request.auth.token?.admin !== true)
    throw new HttpsError("permission-denied", "Admin only.");

  const uid = request.data?.uid;
  if (!uid || typeof uid !== "string")
    throw new HttpsError("invalid-argument", "uid required");

  const db = admin.firestore();

  try {
    const userRef = db.collection("Users").doc(uid);

    await deleteSubcollection(db, userRef, "inventory");
    await deleteSubcollection(db, userRef, "transaction");

    await userRef.delete().catch(() => null);
    await db.collection("Junkshop").doc(uid).delete().catch(() => null);

    const permits = await db.collection("permitRequests").where("uid", "==", uid).get();
    const batch = db.batch();
    permits.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit().catch(() => null);

    await admin.auth().deleteUser(uid);
    return { ok: true, uid };
  } catch (err) {
    console.error("adminDeleteUser error:", err);
    throw new HttpsError("internal", err?.message || String(err));
  }
});

/* ====================================================
   COLLECTOR KYC RETENTION (AUTO-DELETE)
   POLICY:
     - pending        -> delete after 24 hours
     - adminApproved  -> delete after 7 days
     - rejected       -> delete immediately
     - junkshopAccepted -> delete after 7 days
   Deletes:
     ✅ Storage object
     ✅ collectorKYC/{uid} doc
==================================================== */

// ---- time helpers
function hoursFromNow(hours) {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + hours * 60 * 60 * 1000)
  );
}

function daysFromNow(days) {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + days * 24 * 60 * 60 * 1000)
  );
}

// ---- retention policy
function computeCollectorKycDeleteAfter(status) {
  const s = String(status || "").trim().toLowerCase();

  if (s === "pending") return hoursFromNow(24);
  if (s === "adminapproved") return daysFromNow(7);
  if (s === "rejected") return hoursFromNow(0);
  if (s === "junkshopaccepted") return daysFromNow(7);

  return hoursFromNow(24);
}

/* ====================================================
   Ensure collectorKYC has status + deleteAfter
==================================================== */
exports.ensureCollectorKycDefaults = onDocumentWritten(
  { document: "collectorKYC/{uid}", region: "asia-southeast1" },
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data() || {};
    const uid = event.params.uid;

    const status = String(after.status || "pending").trim().toLowerCase();
    const needsStatus = after.status == null;
    const needsDeleteAfter = after.deleteAfter == null;

    if (!needsStatus && !needsDeleteAfter) return;

    const update = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (needsStatus) update.status = status;
    if (needsDeleteAfter)
      update.deleteAfter = computeCollectorKycDeleteAfter(status);

    await afterSnap.ref.set(update, { merge: true });

    logger.info("collectorKYC defaults ensured", { uid, update });
  }
);

/* ====================================================
   Sync status from collectorRequests/{uid}
==================================================== */
exports.syncCollectorKycFromRequestStatus = onDocumentUpdated(
  { document: "collectorRequests/{uid}", region: "asia-southeast1" },
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};
    const uid = event.params.uid;

    const beforeStatus = String(before.status || "").trim().toLowerCase();
    const afterStatus = String(after.status || "").trim().toLowerCase();

    if (!afterStatus || beforeStatus === afterStatus) return;

    const allowed = new Set(["pending", "adminapproved", "rejected", "junkshopaccepted"]);
    if (!allowed.has(afterStatus)) return;

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    const kycRef = db.collection("collectorKYC").doc(uid);
    const kycSnap = await kycRef.get();
    if (!kycSnap.exists) return;

    const kycData = kycSnap.data() || {};
    const storagePath = String(kycData.storagePath || "").trim();

    // ✅ IMMEDIATE DELETE on reject
    if (afterStatus === "rejected") {
      try {
        if (storagePath) {
          await bucket.file(storagePath).delete({ ignoreNotFound: true });
        }
      } catch (err) {
        logger.error("Immediate Storage delete failed", { uid, storagePath, err: String(err) });
      }

      await kycRef.delete().catch((e) => {
        logger.error("Immediate Firestore delete failed", { uid, err: String(e) });
      });

      logger.info("collectorKYC deleted immediately (rejected)", { uid, storagePath });
      return;
    }

    // ✅ otherwise: just set status + deleteAfter for scheduled cleanup
    const deleteAfter = computeCollectorKycDeleteAfter(afterStatus);

    await kycRef.set(
      {
        status: afterStatus,
        deleteAfter,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info("collectorKYC status synced", {
      uid,
      afterStatus,
      deleteAfter: deleteAfter.toDate().toISOString(),
    });
  }
);

/* ====================================================
   Cleanup worker (deletes file + Firestore doc)
==================================================== */
async function cleanupCollectorKyc() {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const now = admin.firestore.Timestamp.now();

  const snap = await db
    .collection("collectorKYC")
    .where("deleteAfter", "<=", now)
    .limit(200)
    .get();

  if (snap.empty) {
    logger.info("collectorKYC cleanup: nothing eligible");
    return { deleted: 0 };
  }

  const batch = db.batch();
  let deleted = 0;

  for (const doc of snap.docs) {
    const uid = doc.id;
    const data = doc.data() || {};

    const storagePath =
      String(data.storagePath || "").trim() ||
      (String(data.kycFileName || "").trim()
        ? `kyc/${uid}/${String(data.kycFileName).trim()}`
        : "");

    try {
      if (storagePath) {
        await bucket.file(storagePath).delete({ ignoreNotFound: true });
      }
    } catch (err) {
      logger.error("Storage delete failed", {
        uid,
        storagePath,
        err: String(err),
      });
    }

    batch.delete(doc.ref);
    deleted++;

    logger.info("collectorKYC deleted", { uid, storagePath });
  }

  await batch.commit();

  logger.info("collectorKYC cleanup finished", { deleted });

  return { deleted };
}

/* ====================================================
   Scheduled cleanup (every hour)
==================================================== */
exports.cleanupCollectorKycByRetention = onSchedule(
  {
    schedule: "every 60 minutes",
    region: "asia-southeast1",
    timeZone: "Asia/Manila",
  },
  async () => {
    const result = await cleanupCollectorKyc();
    logger.info("Scheduled cleanup result", result);
  }
);

/* ====================================================
   Manual cleanup (for testing)
==================================================== */
exports.runCollectorKycCleanupNow = onRequest(
  { region: "asia-southeast1" },
  async (req, res) => {
    try {
      const result = await cleanupCollectorKyc();
      res.status(200).json({ ok: true, ...result });
    } catch (err) {
      logger.error("Manual cleanup crashed", { err: String(err) });
      res.status(500).json({ ok: false, error: String(err) });
    }
  }
);
/* ====================================================
   INVENTORY DEDUCTION
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
        const inventoryRef = db.collection("Users").doc(uid).collection("inventory").doc(item.inventoryDocId);

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

/* ====================================================
   GET DIRECTIONS
==================================================== */
exports.getDirections = onCall(
  {
    region: "asia-southeast1",
    secrets: [GOOGLE_MAPS_API_KEY],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

    const origin = String(request.data?.origin || "").trim();       // "lat,lng"
    const destination = String(request.data?.destination || "").trim(); // "lat,lng"
    const mode = String(request.data?.mode || "driving").trim();

    if (!origin || !destination) {
      throw new HttpsError("invalid-argument", "origin and destination are required");
    }

    const apiKey = GOOGLE_MAPS_API_KEY.value();

    const url =
      "https://maps.googleapis.com/maps/api/directions/json" +
      `?origin=${encodeURIComponent(origin)}` +
      `&destination=${encodeURIComponent(destination)}` +
      `&mode=${encodeURIComponent(mode)}` +
      `&key=${apiKey}`;

    const resp = await fetch(url);
    const data = await resp.json();

    if (data.status && data.status !== "OK") {
      throw new HttpsError("failed-precondition", `Directions failed: ${data.status}`);
    }

    const route0 = data.routes?.[0];
    const points = route0?.overview_polyline?.points || null;

    const leg0 = route0?.legs?.[0];
    const distanceText = leg0?.distance?.text || "";
    const durationText = leg0?.duration?.text || "";
    const durationValueSec = typeof leg0?.duration?.value === "number" ? leg0.duration.value : null;

    if (!points) throw new HttpsError("not-found", "No route/polyline found");

    return { points, distanceText, durationText, durationValueSec };
  }
);