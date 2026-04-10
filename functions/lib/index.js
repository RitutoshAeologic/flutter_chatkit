"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.saveMessage = exports.createChatSession = exports.askAI = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const together_ai_1 = require("together-ai");
const admin = require("firebase-admin");
// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp();
}
// Initialize Together AI client
const together = new together_ai_1.Together({
    apiKey: process.env.TOGETHER_API_KEY,
});
/**
 * Cloud Function: askAI
 */
exports.askAI = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    const { message } = request.data;
    if (!message || typeof message !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'Message must be a string');
    }
    try {
        const response = await together.chat.completions.create({
            model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
            messages: [
                { role: 'system', content: 'You are ChatKit AI, a helpful and premium AI assistant.' },
                { role: 'user', content: message }
            ],
            max_tokens: 512,
            temperature: 0.7,
        });
        return {
            response: ((_b = (_a = response.choices[0]) === null || _a === void 0 ? void 0 : _a.message) === null || _b === void 0 ? void 0 : _b.content) || 'No response',
            status: 'success',
        };
    }
    catch (error) {
        logger.error('Together AI Error:', error);
        throw new https_1.HttpsError('internal', 'Internal error occurred');
    }
});
/**
 * Cloud Function: createChatSession
 */
exports.createChatSession = (0, https_1.onCall)(async (request) => {
    const { userId } = request.data;
    if (!userId)
        throw new https_1.HttpsError('invalid-argument', 'User ID required');
    const db = admin.firestore();
    try {
        const sessionRef = await db
            .collection('users')
            .doc(userId)
            .collection('chat_sessions')
            .add({
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            messageCount: 0,
        });
        return { sessionId: sessionRef.id };
    }
    catch (error) {
        throw new https_1.HttpsError('internal', 'Firestore error');
    }
});
/**
 * Cloud Function: saveMessage
 */
exports.saveMessage = (0, https_1.onCall)(async (request) => {
    const { userId, sessionId, message, response } = request.data;
    if (!userId || !sessionId || !message) {
        throw new https_1.HttpsError('invalid-argument', 'Missing fields');
    }
    const db = admin.firestore();
    try {
        const batch = db.batch();
        const sessionPath = `users/${userId}/chat_sessions/${sessionId}`;
        batch.set(db.collection(`${sessionPath}/messages`).doc(), {
            role: 'user',
            content: message,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.set(db.collection(`${sessionPath}/messages`).doc(), {
            role: 'assistant',
            content: response,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(db.doc(sessionPath), {
            messageCount: admin.firestore.FieldValue.increment(2),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await batch.commit();
        return { status: 'saved' };
    }
    catch (error) {
        throw new https_1.HttpsError('internal', 'Batch write error');
    }
});
//# sourceMappingURL=index.js.map