const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger          = require('firebase-functions/logger');
const admin           = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

exports.dailyMemoryReminder = onSchedule(
  { schedule: '0 14 * * *', timeZone: 'America/New_York' },
  async () => {
    const now    = new Date();
      // set cutoff to today at 00:00 (midnight)
      const cutoff = admin.firestore.Timestamp.fromDate(
        new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0)
      );


    const snap = await db
      .collection('users')
      .where('lastOpened', '<', cutoff)
      .get();

    const msgs = [];
    snap.forEach(doc => {
      const { pushToken } = doc.data();
      if (!pushToken) return;
      msgs.push({
        token: pushToken,
        notification: {
          title: "Your memories await!",
          body:  "Tap to see today’s highlights & past-year throwbacks."
        },
        android: { priority: 'high' },
        apns:    { headers: { 'apns-priority': '10' } }
      });
    });

      logger.info(`Found ${msgs.length} messages to send`);

      while (msgs.length) {
        const batch = msgs.splice(0, 500);
        await admin.messaging().sendAll(batch);
        logger.info(`Sent batch of ${batch.length} notifications`);
      }
  }
);
