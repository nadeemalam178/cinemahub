import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();

/**
 * Triggered when a new user signs up.
 * Creates the user document in Firestore with status='pending'
 * and creates an access request document.
 */
export const onUserCreate = functions.auth.user().onCreate(async (user) => {
  const uid = user.uid;
  const email = user.email ?? "";
  const displayName = user.displayName ?? "";
  const photoURL = user.photoURL ?? "";
  const createdAt = admin.firestore.FieldValue.serverTimestamp();

  const userDoc = {
    email,
    displayName,
    photoURL,
    status: "pending",
    role: "user",
    createdAt,
    lastActive: createdAt,
  };

  const accessRequestDoc = {
    email,
    displayName,
    photoURL,
    status: "pending",
    createdAt,
  };

  const batch = db.batch();
  batch.set(db.collection("users").doc(uid), userDoc);
  batch.set(db.collection("accessRequests").doc(uid), accessRequestDoc);

  await batch.commit();

  functions.logger.info(`Created user doc and access request for ${uid}`);
});

/**
 * Triggered when admin/userStatus/{uid} document is updated.
 * Sets custom claims (admin/owner) based on the status/role in the document.
 * Expected document structure:
 * {
 *   role: "admin" | "owner" | "user",
 *   status: "approved" | "suspended" | "pending",
 *   updatedBy: string (admin uid),
 *   updatedAt: timestamp
 * }
 */
export const onUserStatusUpdate = functions.firestore
  .document("admin/userStatus/{uid}")
  .onUpdate(async (change, context) => {
    const uid = context.params.uid;
    const before = change.before.data();
    const after = change.after.data();

    if (!after) {
      // Document deleted - remove custom claims
      await admin.auth().setCustomUserClaims(uid, { role: "user" });
      functions.logger.info(`Removed custom claims for ${uid} (doc deleted)`);
      return;
    }

    const role = after.role as string | undefined;
    const status = after.status as string | undefined;

    // Only set custom claims for approved admins/owners
    if (status === "approved" && (role === "admin" || role === "owner")) {
      await admin.auth().setCustomUserClaims(uid, { role });
      functions.logger.info(`Set custom claim role=${role} for ${uid}`);
    } else if (status === "suspended" || role === "user") {
      // Remove admin/owner claims for suspended users or demoted users
      await admin.auth().setCustomUserClaims(uid, { role: "user" });
      functions.logger.info(`Reset custom claim to user for ${uid} (status=${status}, role=${role})`);
    }
    // For pending status, keep existing claims (no change)
  });

/**
 * Optional: Callable function for admins to manually set user status/role
 * This creates/updates the admin/userStatus/{uid} document which triggers onUserStatusUpdate
 */
export const setUserStatus = functions.https.onCall(async (data, context) => {
  // Verify caller is admin/owner
  if (!context.auth || !context.auth.token.role || !["admin", "owner"].includes(context.auth.token.role)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only admins can set user status"
    );
  }

  const { targetUid, role, status } = data as {
    targetUid: string;
    role: "admin" | "owner" | "user";
    status: "approved" | "suspended" | "pending";
  };

  if (!targetUid || !role || !status) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing required fields: targetUid, role, status"
    );
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("admin").doc("userStatus").collection("users").doc(targetUid).set({
    role,
    status,
    updatedBy: context.auth.uid,
    updatedAt: now,
  }, { merge: true });

  return { success: true };
});