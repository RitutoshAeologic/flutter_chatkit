"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteSession = exports.loadMessages = exports.listSessions = exports.chat = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
exports.chat = functions.https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in to chat.");
    }
    const { message, sessionId, systemPrompt, temperature, maxTokens } = data;
    const uid = context.auth.uid;
    if (!message || !sessionId) {
        throw new functions.https.HttpsError("invalid-argument", "Missing message or sessionId");
    }
    // Get Together API key from environment config
    // firebase functions:config:set together.api_key="YOUR_KEY_HERE"
    const apiKey = ((_a = functions.config().together) === null || _a === void 0 ? void 0 : _a.api_key) || process.env.TOGETHER_API_KEY;
    if (!apiKey) {
        throw new functions.https.HttpsError("failed-precondition", "Together API key not configured");
    }
    try {
        // Note: Together AI free tier is suitable for testing.
        const response = await fetch("https://api.together.xyz/v1/chat/completions", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${apiKey}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                model: "togethercomputer/GPT-NeoXT-Chat-Base-20B",
                messages: [
                    { role: "system", content: systemPrompt || "You are a friendly AI." },
                    { role: "user", content: message }
                ],
                temperature: temperature || 0.7,
                max_tokens: maxTokens || 512
            })
        });
        if (!response.ok) {
            const errBody = await response.text();
            console.error("Together API Error:", errBody);
            throw new functions.https.HttpsError("internal", "Error from AI provider");
        }
        const json = await response.json();
        const reply = json.choices[0].message.content;
        // Save metadata to Firestore
        const sessionRef = db.collection("users").doc(uid).collection("sessions").doc(sessionId);
        await sessionRef.set({
            displayTitle: message.substring(0, 30) + (message.length > 30 ? "..." : ""),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            messageCount: admin.firestore.FieldValue.increment(2)
        }, { merge: true });
        // Save user message
        const userMsgRef = sessionRef.collection("messages").doc();
        await userMsgRef.set({
            content: message,
            role: "user",
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
        // Save assistant reply
        const astMsgRef = sessionRef.collection("messages").doc();
        await astMsgRef.set({
            content: reply,
            role: "assistant",
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });
        return { reply, messageId: astMsgRef.id };
    }
    catch (error) {
        console.error("Chat error:", error);
        throw new functions.https.HttpsError("internal", "Failed to communicate with AI");
    }
});
exports.listSessions = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const uid = context.auth.uid;
    const snapshot = await db.collection("users").doc(uid).collection("sessions")
        .orderBy("lastUpdated", "desc").get();
    return snapshot.docs.map(doc => ({
        id: doc.id,
        displayTitle: doc.data().displayTitle || "New Chat",
        messageCount: doc.data().messageCount || 0
    }));
});
exports.loadMessages = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const { sessionId } = data;
    if (!sessionId)
        throw new functions.https.HttpsError("invalid-argument", "Missing sessionId");
    const uid = context.auth.uid;
    const snapshot = await db.collection("users").doc(uid).collection("sessions").doc(sessionId)
        .collection("messages").orderBy("timestamp", "asc").get();
    return snapshot.docs.map(doc => {
        const d = doc.data();
        return {
            id: doc.id,
            content: d.content,
            role: d.role,
            timestamp: d.timestamp ? d.timestamp.toDate().toISOString() : new Date().toISOString()
        };
    });
});
exports.deleteSession = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const { id } = data;
    if (!id)
        throw new functions.https.HttpsError("invalid-argument", "Missing session id");
    const uid = context.auth.uid;
    await db.collection("users").doc(uid).collection("sessions").doc(id).delete();
    return { success: true };
});
//# sourceMappingURL=index.js.map