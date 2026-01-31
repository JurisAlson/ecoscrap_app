const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.deductInventoryOnTransactionCreate = functions.firestore
  .document("Junkshop/{shopId}/transaction/{txId}")
  .onCreate(async (snap, context) => {
    const { shopId } = context.params;
    const data = snap.data();

    if (!data || !Array.isArray(data.items)) {
      console.log("No items array found, skipping");
      return null;
    }

    const db = admin.firestore();

    return db.runTransaction(async (transaction) => {
      for (const item of data.items) {
        const inventoryDocId = item.inventoryDocId;
        const weightKg = Number(item.weightKg);

        if (!inventoryDocId || weightKg <= 0) continue;

        const inventoryRef = db
          .collection("Junkshop")
          .doc(shopId)
          .collection("inventory")
          .doc(inventoryDocId);

        const inventorySnap = await transaction.get(inventoryRef);

        if (!inventorySnap.exists) {
          console.warn(`Inventory item not found: ${inventoryDocId}`);
          continue;
        }

        const currentKg =
          Number(inventorySnap.data().unitsKg) || 0;

        const newKg = Math.max(currentKg - weightKg, 0);

        transaction.update(inventoryRef, {
          unitsKg: newKg,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // mark transaction as processed
      transaction.update(snap.ref, {
        inventoryDeducted: true,
        inventoryDeductedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return null;
    });
  });
