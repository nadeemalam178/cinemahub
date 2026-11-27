import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();

type UserRole = "owner" | "admin" | "user";
type UserStatus = "approved" | "pending" | "suspended";

const VALID_ROLES = new Set<UserRole>(["owner", "admin", "user"]);
const VALID_STATUSES = new Set<UserStatus>(["approved", "pending", "suspended"]);

/**
 * Triggered when a new user signs up.
 * Creates the user document in Firestore and access request document.
 * Bootstraps the first user (or configured OWNER_EMAIL) as owner + approved
 * using an atomic bootstrap sentinel document so concurrent signups cannot race.
 */
export const onUserCreate = functions.auth.user().onCreate(async (user) => {
  const uid = user.uid;
  const email = user.email ?? "";
  const displayName = user.displayName ?? "";
  const photoURL = user.photoURL ?? "";
  const now = admin.firestore.FieldValue.serverTimestamp();

  const configuredOwnerEmail = (process.env.OWNER_EMAIL ?? "").trim().toLowerCase();
  const isConfiguredOwner =
    configuredOwnerEmail.length > 0 && email.toLowerCase() === configuredOwnerEmail;

  const bootstrapRef = db.collection("admin").doc("bootstrap");
  const userRef = db.collection("users").doc(uid);
  const requestRef = db.collection("accessRequests").doc(uid);

  const assignedRole = await db.runTransaction<UserRole>(async (tx) => {
    const bootstrapSnap = await tx.get(bootstrapRef);
    const shouldMakeOwner = isConfiguredOwner || !bootstrapSnap.exists;

    const role: UserRole = shouldMakeOwner ? "owner" : "user";
    const status: UserStatus = shouldMakeOwner ? "approved" : "pending";

    if (shouldMakeOwner && !bootstrapSnap.exists) {
      tx.set(bootstrapRef, {
        ownerUid: uid,
        ownerEmail: email,
        bootstrappedAt: now,
      });
    }

    tx.set(
      userRef,
      {
        uid,
        email,
        displayName,
        photoURL,
        status,
        role,
        createdAt: now,
        lastActive: now,
      },
      { merge: true }
    );

    tx.set(
      requestRef,
      {
        uid,
        email,
        displayName,
        photoURL,
        status,
        createdAt: now,
      },
      { merge: true }
    );

    return role;
  });

  await admin.auth().setCustomUserClaims(uid, { role: assignedRole });

  functions.logger.info(
    `Created user doc and access request for ${uid} (role=${assignedRole})`
  );
});

/**
 * Triggered when admin/userStatus/users/{uid} document is created, updated, or deleted.
 * Sets custom claims based on status/role and synchronizes users/{uid} and accessRequests/{uid}.
 */
export const onUserStatusUpdate = functions.firestore
  .document("admin/userStatus/users/{uid}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const after = change.after.data();

    // Handle delete event
    if (!after) {
      await admin.auth().setCustomUserClaims(uid, { role: "user" }).catch((e) => {
        functions.logger.error(`Failed to reset claims on delete for ${uid}: ${e}`);
      });

      const now = admin.firestore.FieldValue.serverTimestamp();
      await Promise.all([
        db
          .collection("users")
          .doc(uid)
          .set(
            {
              role: "user",
              status: "suspended",
              updatedAt: now,
            },
            { merge: true }
          )
          .catch((e) => functions.logger.error(`Failed to sync users/${uid} on delete: ${e}`)),
        db
          .collection("accessRequests")
          .doc(uid)
          .set(
            {
              status: "suspended",
              updatedAt: now,
            },
            { merge: true }
          )
          .catch((e) =>
            functions.logger.error(`Failed to sync accessRequests/${uid} on delete: ${e}`)
          ),
      ]);

      functions.logger.info(`Removed custom claims for ${uid} (doc deleted)`);
      return;
    }

    const rawStatus = after.status as string | undefined;
    const status: UserStatus =
      rawStatus && VALID_STATUSES.has(rawStatus as UserStatus)
        ? (rawStatus as UserStatus)
        : "pending";

    let role = after.role as UserRole | undefined;
    if (!role || !VALID_ROLES.has(role)) {
      const existingUserSnap = await db.collection("users").doc(uid).get();
      const existingRole = existingUserSnap.data()?.role as string | undefined;
      role =
        existingRole && VALID_ROLES.has(existingRole as UserRole)
          ? (existingRole as UserRole)
          : "user";
    }

    const updatedBy = (after.updatedBy as string | undefined) ?? null;
    const updatedAt = after.updatedAt ?? admin.firestore.FieldValue.serverTimestamp();

    await Promise.all([
      db
        .collection("users")
        .doc(uid)
        .set(
          {
            role,
            status,
            updatedBy,
            updatedAt,
          },
          { merge: true }
        )
        .catch((e) => functions.logger.error(`Failed to sync users/${uid}: ${e}`)),
      db
        .collection("accessRequests")
        .doc(uid)
        .set(
          {
            status,
            updatedBy,
            updatedAt,
          },
          { merge: true }
        )
        .catch((e) => functions.logger.error(`Failed to sync accessRequests/${uid}: ${e}`)),
    ]);

    if (status === "approved" && (role === "admin" || role === "owner")) {
      await admin.auth().setCustomUserClaims(uid, { role });
      functions.logger.info(`Set custom claim role=${role} for ${uid}`);
    } else if (status === "suspended" || role === "user") {
      await admin.auth().setCustomUserClaims(uid, { role: "user" });
      functions.logger.info(`Set custom claim role=user for ${uid} (status=${status}, role=${role})`);
    }
  });

/**
 * Callable function for admins/owners to set user status/role.
 */
export const setUserStatus = functions.https.onCall(async (data, context) => {
  const callerRole = context.auth?.token?.role as string | undefined;
  if (!context.auth || !callerRole || !["admin", "owner"].includes(callerRole)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only admins can set user status"
    );
  }

  const { targetUid, role, status } = (data ?? {}) as {
    targetUid?: string;
    role?: UserRole;
    status?: UserStatus;
  };

  if (
    !targetUid ||
    !role ||
    !status ||
    !VALID_ROLES.has(role) ||
    !VALID_STATUSES.has(status)
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid or missing targetUid, role, or status"
    );
  }

  if (role === "owner" && callerRole !== "owner") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only an owner can assign the owner role"
    );
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  await db
    .collection("admin")
    .doc("userStatus")
    .collection("users")
    .doc(targetUid)
    .set(
      {
        role,
        status,
        updatedBy: context.auth.uid,
        updatedAt: now,
      },
      { merge: true }
    );

  return { success: true };
});
