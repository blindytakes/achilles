const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Enhanced daily memory reminder with admin controls
exports.dailyMemoryReminder = onSchedule(
  { schedule: '0 * * * *', timeZone: 'America/New_York' }, // Run every hour
  async () => {
    const adminConfig = await getAdminNotificationConfig();
    
    // Check if admin has disabled daily reminders
    if (!adminConfig?.dailyReminder?.enabled) {
      logger.info('Daily reminders disabled by admin');
      return;
    }

    const now = new Date();
    const currentHour = now.getHours();
    
    // Get admin-defined sending times or default to 2 PM
    const sendingHours = adminConfig?.dailyReminder?.sendingHours || [14];
    
    // Only run at specified hours
    if (!sendingHours.includes(currentHour)) {
      return;
    }

    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0)
    );

    try {
      // Build query based on admin targeting rules
      let query = db.collection('users')
        .where('lastOpened', '<', cutoff);
      
      // Add admin targeting filters
      if (adminConfig?.dailyReminder?.targeting?.requireNotificationEnabled !== false) {
        query = query.where('notificationSettings.dailyReminderEnabled', '==', true);
      }
      
      const snap = await query.get();
      const messages = [];
      
      snap.forEach(doc => {
        const userData = doc.data();
        const { pushToken, notificationSettings = {}, createdAt } = userData;
        
        if (!pushToken) return;

        // Apply admin targeting rules
        if (!shouldSendToUser(userData, adminConfig?.dailyReminder?.targeting)) {
          return;
        }

        // Get messages with admin priority
        let customMessages = notificationSettings.customMessages || [
          "Your memories await!",
          "Discover photos from this day in past years!",
          "Time for your daily throwback!"
        ];
        
        if (adminConfig?.dailyReminder?.messages?.length > 0) {
          customMessages = adminConfig.dailyReminder.messages;
        }
        
        const randomMessage = customMessages[Math.floor(Math.random() * customMessages.length)];
        
        // Use admin-defined title or default
        const title = adminConfig?.dailyReminder?.title || "Throwbaks";
        
        messages.push({
          token: pushToken,
          notification: {
            title: title,
            body: randomMessage
          },
          data: {
            type: "daily_reminder",
            openScreen: adminConfig?.dailyReminder?.deepLink || "today_memories",
            campaignId: adminConfig?.dailyReminder?.campaignId || "daily_reminder"
          },
          android: { 
            priority: 'high',
            notification: {
              icon: "ic_notification",
              color: "#13B513"
            }
          },
          apns: { 
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                badge: 1,
                sound: "default"
              }
            }
          }
        });
      });

      logger.info(`Prepared ${messages.length} daily reminder notifications at hour ${currentHour}`);

      await sendNotificationsInBatches(messages, 'daily_reminder');
    } catch (error) {
      logger.error('Error in dailyMemoryReminder:', error);
    }
  }
);

// Enhanced user targeting logic
function shouldSendToUser(userData, targeting) {
  if (!targeting) return true;
  
  const now = new Date();
  const { 
    minDaysSinceSignup,
    maxDaysSinceSignup,
    minDaysSinceLastOpen,
    maxDaysSinceLastOpen,
    requirePhotosUploaded,
    excludeAnonymous,
    includeOnlyTimeZones,
    excludeUserIds
  } = targeting;
  
  // Check signup date
  if (minDaysSinceSignup || maxDaysSinceSignup) {
    const createdAt = userData.createdAt?.toDate() || new Date();
    const daysSinceSignup = (now - createdAt) / (1000 * 60 * 60 * 24);
    
    if (minDaysSinceSignup && daysSinceSignup < minDaysSinceSignup) return false;
    if (maxDaysSinceSignup && daysSinceSignup > maxDaysSinceSignup) return false;
  }
  
  // Check last opened date
  if (minDaysSinceLastOpen || maxDaysSinceLastOpen) {
    const lastOpened = userData.lastOpened?.toDate() || new Date(0);
    const daysSinceLastOpen = (now - lastOpened) / (1000 * 60 * 60 * 24);
    
    if (minDaysSinceLastOpen && daysSinceLastOpen < minDaysSinceLastOpen) return false;
    if (maxDaysSinceLastOpen && daysSinceLastOpen > maxDaysSinceLastOpen) return false;
  }
  
  // Check if user has photos (if required)
  if (requirePhotosUploaded && !userData.hasUploadedPhotos) return false;
  
  // Exclude anonymous users
  if (excludeAnonymous && userData.isAnonymous) return false;
  
  // Check timezone
  if (includeOnlyTimeZones?.length > 0) {
    const userTimeZone = userData.notificationSettings?.timeZone || 'America/New_York';
    if (!includeOnlyTimeZones.includes(userTimeZone)) return false;
  }
  
  // Exclude specific users
  if (excludeUserIds?.includes(userData.uid)) return false;
  
  return true;
}

// Get admin notification configuration
async function getAdminNotificationConfig() {
  try {
    const adminDoc = await db.collection('admin').doc('notificationConfig').get();
    return adminDoc.exists ? adminDoc.data() : null;
  } catch (error) {
    logger.warn('Could not fetch admin notification config:', error);
    return null;
  }
}
async function sendNotificationsInBatches(messages, campaignType) {
  let totalSent = 0;
  let totalFailed = 0;
  
  while (messages.length) {
    const batch = messages.splice(0, 500);
    const response = await admin.messaging().sendAll(batch);
    
    totalSent += response.successCount;
    totalFailed += response.failureCount;
    
    logger.info(`Sent batch of ${batch.length} notifications. Success: ${response.successCount}, Failures: ${response.failureCount}`);
    
    // Handle failed tokens
    if (response.failureCount > 0) {
      const failedTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push(batch[idx].token);
          logger.warn(`Failed to send to token: ${batch[idx].token}, Error: ${resp.error?.message}`);
        }
      });
      
      await cleanupInvalidTokens(failedTokens);
    }
  }
  
  // Log final results
  await db.collection('admin').doc('notificationLogs').collection('logs').add({
    campaignType,
    totalSent,
    totalFailed,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
  });
  
  logger.info(`Campaign ${campaignType} completed. Total sent: ${totalSent}, Total failed: ${totalFailed}`);
}

// Clean up invalid FCM tokens
async function cleanupInvalidTokens(invalidTokens) {
  const batch = db.batch();
  
  for (const token of invalidTokens) {
    try {
      const userQuery = await db
        .collection('users')
        .where('pushToken', '==', token)
        .limit(1)
        .get();
      
      if (!userQuery.empty) {
        const userDoc = userQuery.docs[0];
        batch.update(userDoc.ref, { pushToken: admin.firestore.FieldValue.delete() });
      }
    } catch (error) {
      logger.warn(`Error cleaning up token ${token}:`, error);
    }
  }
  
  await batch.commit();
  logger.info(`Cleaned up ${invalidTokens.length} invalid tokens`);
}

// Custom notification campaign runner
exports.runCustomCampaign = onSchedule(
  { schedule: '*/30 * * * *', timeZone: 'America/New_York' }, // Check every 30 minutes
  async () => {
    try {
      const now = new Date();
      
      // Get pending campaigns
      const campaignsSnap = await db
        .collection('admin')
        .doc('campaigns')
        .collection('pending')
        .where('scheduledFor', '<=', admin.firestore.Timestamp.fromDate(now))
        .where('status', '==', 'pending')
        .get();

      for (const campaignDoc of campaignsSnap.docs) {
        const campaign = campaignDoc.data();
        await executeCampaign(campaign, campaignDoc.id);
        
        // Mark as completed
        await campaignDoc.ref.update({
          status: 'completed',
          completedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }
    } catch (error) {
      logger.error('Error in runCustomCampaign:', error);
    }
  }
);

// Execute a specific campaign
async function executeCampaign(campaign, campaignId) {
  try {
    logger.info(`Executing campaign: ${campaignId}`);
    
    // Build user query based on campaign targeting
    let query = db.collection('users');
    
    // Apply targeting filters
    if (campaign.targeting) {
      if (campaign.targeting.userSegment === 'inactive_3_days') {
        const threeDaysAgo = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 3 * 24 * 60 * 60 * 1000)
        );
        query = query.where('lastOpened', '<', threeDaysAgo);
      } else if (campaign.targeting.userSegment === 'inactive_7_days') {
        const sevenDaysAgo = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
        );
        query = query.where('lastOpened', '<', sevenDaysAgo);
      } else if (campaign.targeting.userSegment === 'new_users') {
        const sevenDaysAgo = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
        );
        query = query.where('createdAt', '>', sevenDaysAgo);
      }
      
      // Add more targeting criteria
      if (campaign.targeting.requireNotificationEnabled !== false) {
        query = query.where('notificationSettings.enabled', '==', true);
      }
    }
    
    const usersSnap = await query.get();
    const messages = [];
    
    usersSnap.forEach(doc => {
      const userData = doc.data();
      const { pushToken } = userData;
      
      if (!pushToken) return;
      
      // Apply additional targeting rules
      if (!shouldSendToUser(userData, campaign.targeting)) {
        return;
      }
      
      // Randomly select message
      const randomMessage = campaign.messages[Math.floor(Math.random() * campaign.messages.length)];
      
      messages.push({
        token: pushToken,
        notification: {
          title: campaign.title || "Throwbaks",
          body: randomMessage
        },
        data: {
          type: "custom_campaign",
          campaignId: campaignId,
          openScreen: campaign.deepLink || "main"
        },
        android: { 
          priority: campaign.priority || 'normal',
          notification: {
            icon: "ic_notification",
            color: "#13B513"
          }
        },
        apns: { 
          headers: { 'apns-priority': campaign.priority === 'high' ? '10' : '5' },
          payload: {
            aps: {
              badge: 1,
              sound: "default"
            }
          }
        }
      });
    });
    
    logger.info(`Campaign ${campaignId}: prepared ${messages.length} notifications`);
    await sendNotificationsInBatches(messages, campaignId);
    
    // Log campaign results
    await db.collection('admin').doc('campaignResults').collection('results').add({
      campaignId,
      sentCount: messages.length,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      campaign: campaign
    });
    
  } catch (error) {
    logger.error(`Error executing campaign ${campaignId}:`, error);
  }
}

// Weekly digest notification
exports.weeklyDigest = onSchedule(
  { schedule: '0 10 * * 0', timeZone: 'America/New_York' }, // Sundays at 10 AM
  async () => {
    try {
      const snap = await db
        .collection('users')
        .where('notificationSettings.weeklyDigestEnabled', '==', true)
        .get();

      const messages = [];
      
      snap.forEach(doc => {
        const { pushToken } = doc.data();
        if (!pushToken) return;

        messages.push({
          token: pushToken,
          notification: {
            title: "Your Weekly Memory Recap",
            body: "See all the amazing throwbacks from this week!"
          },
          data: {
            type: "weekly_digest",
            openScreen: "weekly_recap"
          },
          android: { priority: 'normal' },
          apns: { headers: { 'apns-priority': '5' } }
        });
      });

      if (messages.length > 0) {
        const response = await admin.messaging().sendAll(messages);
        logger.info(`Weekly digest sent. Success: ${response.successCount}, Failures: ${response.failureCount}`);
      }
    } catch (error) {
      logger.error('Error in weeklyDigest:', error);
    }
  }
);