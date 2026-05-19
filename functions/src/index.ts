import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();
const db = admin.firestore();

// Trigger on any create/update/delete for assessments
export const syncBestScore = functions.firestore
  .document('assessments/{assessmentId}')
  .onWrite(async (change) => {
    try {
      // After snapshot for create/update; if delete then after is empty
      const after = change.after.exists ? (change.after.data() as any) : null;
      const before = change.before.exists ? (change.before.data() as any) : null;

      // Determine userId and activityKey from whichever exists (prefer after)
      const userId = after?.userId ?? before?.userId;
      const activityKey = after?.activityKey ?? before?.activityKey;

      if (!userId || !activityKey) {
        // nothing to do
        return;
      }

      // Query for user's best score for this activity
      const bestSnap = await db
        .collection('assessments')
        .where('userId', '==', userId)
        .where('activityKey', '==', activityKey)
        .orderBy('score', 'desc')
        .limit(1)
        .get();

      const id = `${activityKey}_${userId}`;

      if (bestSnap.empty) {
        // No assessments remain for this user/activity -> remove best_scores doc if exists
        try {
          await db.collection('best_scores').doc(id).delete();
        } catch (err) {
          // deletion might fail if doc doesn't exist or transient error — log and continue
          console.warn(`syncBestScore: failed to delete best_scores/${id}:`, err);
        }
        return;
      }

      const bestDoc = bestSnap.docs[0].data() as any;
      const bestScore = bestDoc.score;
      const bestTimestamp = bestDoc.timestamp ?? admin.firestore.FieldValue.serverTimestamp();
      const displayName = bestDoc.displayName ?? bestDoc.userId ?? 'Athlete';

      await db.collection('best_scores').doc(id).set(
        {
          userId,
          activityKey,
          displayName,
          score: bestScore,
          timestamp: bestTimestamp,
        },
        { merge: true }
      );
    } catch (err) {
      console.error('syncBestScore error:', err);
      // Let the error bubble so CF logs a failure (optional)
      throw err;
    }
  });
