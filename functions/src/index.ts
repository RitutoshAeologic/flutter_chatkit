import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Cloud Function: askAI (Groq Edition)
 */
export const askAI = onCall(async (request) => {
  const { message } = request.data;
  const GROQ_API_KEY = process.env.GROQ_API_KEY;

  if (!message || typeof message !== 'string') {
    throw new HttpsError('invalid-argument', 'Message must be a string');
  }

  if (!GROQ_API_KEY) {
    throw new HttpsError('failed-precondition', 'Groq API Key not configured');
  }

  try {
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GROQ_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [
            { role: "system", content: "You are ChatKit AI, a premium assistant." },
            { role: "user", content: message }
        ],
        max_tokens: 1024,
        temperature: 0.7
      })
    });

    if (!response.ok) {
        const errorData = await response.json();
        logger.error('Groq API Error Detail:', errorData);
        throw new Error(`Groq API Error: ${response.statusText}`);
    }

    const data: any = await response.json();
    return {
      response: data.choices[0]?.message?.content || 'No response',
      status: 'success',
    };
  } catch (error) {
    logger.error('Groq Integration Error:', error);
    throw new HttpsError('internal', 'Consult cloud logs for details');
  }
});

/**
 * Cloud Function: createChatSession (Realtime Database version)
 */
export const createChatSession = onCall(async (request) => {
  const { userId } = request.data;
  if (!userId) throw new HttpsError('invalid-argument', 'User ID required');

  const db = admin.database();
  try {
    const sessionRef = db.ref(`users/${userId}/chat_sessions`).push();
    await sessionRef.set({
      title: 'New Chat',
      createdAt: admin.database.ServerValue.TIMESTAMP,
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    });

    return { sessionId: sessionRef.key };
  } catch (error) {
    throw new HttpsError('internal', 'Database error');
  }
});

/**
 * Cloud Function: saveMessage (Realtime Database version)
 */
export const saveMessage = onCall(async (request) => {
  const { userId, sessionId, message, response } = request.data;
  if (!userId || !sessionId || !message) {
    throw new HttpsError('invalid-argument', 'Missing fields');
  }

  const db = admin.database();
  try {
    const messagesRef = db.ref(`chat_messages/${sessionId}`);
    
    const userMsgRef = messagesRef.push();
    await userMsgRef.set({
      role: 'user',
      content: message,
      createdAt: admin.database.ServerValue.TIMESTAMP,
    });

    const aiMsgRef = messagesRef.push();
    await aiMsgRef.set({
      role: 'assistant',
      content: response,
      createdAt: admin.database.ServerValue.TIMESTAMP,
    });

    await db.ref(`users/${userId}/chat_sessions/${sessionId}`).update({
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    });

    return { status: 'saved' };
  } catch (error) {
    throw new HttpsError('internal', 'Write error');
  }
});
