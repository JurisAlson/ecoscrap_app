const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

const { logger } = require("firebase-functions");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");

/* ================================
   EXISTING: Deduct inventory on transaction create
   (UNCHANGED)
================================ */

exports.deductInventoryOnTransactionCreate = onDocumentCreated(
  {
    document: "Junkshop/{shopId}/transaction/{txId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const { shopId, txId } = event.params;
    const snap = event.data;

    if (!snap) {
      logger.warn("No snapshot data, skipping");
      return;
    }

    const data = snap.data();

    logger.info("FUNCTION FIRED", { shopId, txId });
    logger.info("TX DATA", data);

    if (!data || !Array.isArray(data.items)) {
      logger.info("No items array found, skipping");
      return;
    }

    const db = admin.firestore();

    await db.runTransaction(async (t) => {
      for (const item of data.items) {
        const inventoryDocId = item.inventoryDocId;
        const weightKg = Number(item.weightKg);

        if (!inventoryDocId || !Number.isFinite(weightKg) || weightKg <= 0) {
          continue;
        }

        const inventoryRef = db
          .collection("Junkshop")
          .doc(shopId)
          .collection("inventory")
          .doc(inventoryDocId);

        const inventorySnap = await t.get(inventoryRef);

        if (!inventorySnap.exists) {
          logger.warn("Inventory item not found", { inventoryDocId });
          continue;
        }

        const currentKg = Number(inventorySnap.data().unitsKg) || 0;
        const newKg = Math.max(currentKg - weightKg, 0);

        t.update(inventoryRef, {
          unitsKg: newKg,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // mark transaction processed (optional but helpful)
      t.update(snap.ref, {
        inventoryDeducted: true,
        inventoryDeductedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
);

/* ================================
   NEW: wrapDek (Firebase-only; uses Functions Secret MASTER_KEY_B64)
================================ */

exports.wrapDek = onCall(
  {
    region: "asia-southeast1",
    secrets: ["MASTER_KEY_B64"],
  },
  async (request) => {
    if (!request.auth) {
      throw new Error("Unauthenticated");
    }

    const dekB64 = request.data?.dekB64;
    if (typeof dekB64 !== "string") {
      throw new Error("dekB64 required");
    }

    const dek = Buffer.from(dekB64, "base64");
    if (dek.length !== 32) {
      throw new Error("DEK must be 32 bytes");
    }

    const masterKeyB64 = process.env.MASTER_KEY_B64;
    if (!masterKeyB64) {
      throw new Error("MASTER_KEY_B64 not set");
    }

    const masterKey = Buffer.from(masterKeyB64, "base64");
    if (masterKey.length !== 32) {
      throw new Error("MASTER_KEY_B64 must decode to 32 bytes");
    }

    // Wrap DEK using AES-256-GCM
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", masterKey, iv);

    const wrapped = Buffer.concat([cipher.update(dek), cipher.final()]);
    const tag = cipher.getAuthTag(); // 16 bytes

    return {
      wrappedDekB64: wrapped.toString("base64"),
      wrapIvB64: iv.toString("base64"),
      wrapTagB64: tag.toString("base64"),
      wrapAlg: "AES-256-GCM",
    };
  }
);
