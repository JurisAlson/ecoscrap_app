const admin = require("firebase-admin");
const { logger } = require("firebase-functions");

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");

admin.initializeApp();

/* ====================================================
   Helper — subtract days
==================================================== */
function daysAgo(days) {
  const ms = days * 24 * 60 * 60 * 1000;
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - ms)
  );
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

    if (
      before.approved !== true &&
      after.approved === true &&
      !after.approvedAt
    ) {
      logger.info("Auto setting approvedAt", {
        requestId: event.params.requestId,
      });

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

  /* ---------- QUERY UNAPPROVED ---------- */
  const unapprovedSnap = await db
    .collection("permitRequests")
    .where("approved", "==", false)
    .where("submittedAt", "<=", cutoffUnapproved)
    .limit(200)
    .get();

  /* ---------- QUERY APPROVED ---------- */
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

  /* ---------- DELETE FILES ---------- */
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

      logger.info("Permit file removed", {
        requestId: doc.id,
        permitPath,
      });

    } catch (err) {
      logger.error("Permit deletion failed", {
        requestId: doc.id,
        err: String(err),
      });
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
