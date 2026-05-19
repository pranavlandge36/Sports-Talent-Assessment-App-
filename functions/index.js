// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * updateLeaderboardOnAssessmentCreate
 *
 * Trigger: onCreate for documents in `assessments/{assessmentId}`
 * Behavior:
 *  - Expects assessment docs to contain at least: userId (string), activityKey (string), score (number)
 *  - Maintains sanitized leaderboard docs at: /leaderboard/{userId}_{activityKey}
 *  - Writes only when the user's best improves (strictly greater). Uses a transaction to avoid races.
 *
 * Leaderboard doc shape:
 * {
 *   userId: string,
 *   activityKey: string,
 *   displayName: string|null,
 *   bestScore: number,
 *   updatedAt: Timestamp
 * }
 */
exports.updateLeaderboardOnAssessmentCreate = functions.firestore
    .document("assessments/{assessmentId}")
    .onCreate(async (snap, context) => {
      try {
        const data = snap.data();
        if (!data) {
          console.log("Empty assessment document, skipping:", context.params.assessmentId);
          return null;
        }

        const userId = data.userId;
        const activityKey = data.activityKey;
        const rawScore = data.score;

        // Basic validation
        const score = typeof rawScore === "number" ? rawScore : Number(rawScore);
        if (!userId || !activityKey || isNaN(score)) {
          console.log("Invalid assessment fields; skipping:", {
            id: context.params.assessmentId,
            userId,
            activityKey,
            score: rawScore,
          });
          return null;
        }

        const docId = `${userId}_${activityKey}`;
        const lbRef = admin.firestore().collection("leaderboard").doc(docId);

        await admin.firestore().runTransaction(async (tx) => {
          const lbSnap = await tx.get(lbRef);
          if (!lbSnap.exists) {
          // Create initial leaderboard entry
            tx.set(lbRef, {
              userId,
              activityKey,
              displayName: data.displayName || null,
              bestScore: score,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log("Created leaderboard entry:", docId, score);
            return;
          }

          const existing = lbSnap.data() || {};
          const existingScore = typeof existing.bestScore === "number" ? existing.bestScore : Number(existing.bestScore || 0);

          if (score > existingScore) {
            tx.update(lbRef, {
              bestScore: score,
              displayName: data.displayName || existing.displayName || null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log("Updated leaderboard entry:", docId, "from", existingScore, "to", score);
          } else {
            console.log("No leaderboard update needed for", docId, "existingBest=", existingScore, "new=", score);
          }
        });

        return null;
      } catch (err) {
        console.error("updateLeaderboardOnAssessmentCreate error:", err);
        return null;
      }
    });
