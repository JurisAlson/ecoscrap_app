const admin = require("firebase-admin");
admin.initializeApp();

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

exports.deductInventoryOnTransactionCreate = onDocumentCreated(
  { document: "Junkshop/{shopId}/transaction/{txId}", region: "asia-southeast1" },
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
