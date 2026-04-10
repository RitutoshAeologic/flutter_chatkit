import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { Together } from 'together-ai';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

// Initialize Together AI client
const together = new Together({
  apiKey: process.env.TOGETHER_API_KEY,
});

/**
 * Cloud Function: askAI
 */
export const askAI = onCall(async (request) => {
  const { message } = request.data;

  if (!message || typeof message !== 'string') {
    throw new HttpsError('invalid-argument', 'Message must be a string');
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
      response: response.choices[0]?.message?.content || 'No response',
      status: 'success',
    };
  } catch (error) {
    logger.error('Together AI Error:', error);
    throw new HttpsError('internal', 'Internal error occurred');
  }
});

/**
 * Cloud Function: createChatSession
 */
export const createChatSession = onCall(async (request) => {
  const { userId } = request.data;
  if (!userId) throw new HttpsError('invalid-argument', 'User ID required');

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
  } catch (error) {
    throw new HttpsError('internal', 'Firestore error');
  }
});

/**
 * Cloud Function: saveMessage
 */
export const saveMessage = onCall(async (request) => {
  const { userId, sessionId, message, response } = request.data;
  if (!userId || !sessionId || !message) {
    throw new HttpsError('invalid-argument', 'Missing fields');
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
  } catch (error) {
    throw new HttpsError('internal', 'Batch write error');
  }
});
