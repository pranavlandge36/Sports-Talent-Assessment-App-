"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncBestScore = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
const db = admin.firestore();
// Trigger on any create/update/delete for assessments
exports.syncBestScore = functions.firestore
    .document('assessments/{assessmentId}')
    .onWrite(async (change) => {
    try {
        // After snapshot for create/update; if delete then after is empty
        const after = change.after.exists ? change.after.data() : null;
        const before = change.before.exists ? change.before.data() : null;
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
            }
            catch (err) {
                // deletion might fail if doc doesn't exist or transient error — log and continue
                console.warn(`syncBestScore: failed to delete best_scores/${id}:`, err);
            }
            return;
        }
        const bestDoc = bestSnap.docs[0].data();
        const bestScore = bestDoc.score;
        const bestTimestamp = bestDoc.timestamp ?? admin.firestore.FieldValue.serverTimestamp();
        const displayName = bestDoc.displayName ?? bestDoc.userId ?? 'Athlete';
        await db.collection('best_scores').doc(id).set({
            userId,
            activityKey,
            displayName,
            score: bestScore,
            timestamp: bestTimestamp,
        }, { merge: true });
    }
    catch (err) {
        console.error('syncBestScore error:', err);
        // Let the error bubble so CF logs a failure (optional)
        throw err;
    }
});
