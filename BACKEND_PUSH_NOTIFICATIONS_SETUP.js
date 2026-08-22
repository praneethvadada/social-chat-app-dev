/**
 * BACKEND IMPLEMENTATION - Node.js with Firebase Admin SDK
 * 
 * This file shows how to implement push notifications on the backend
 * Copy this logic into your Node.js/Express backend
 */

const admin = require('firebase-admin');
const express = require('express');
const router = express.Router();

// Initialize Firebase Admin SDK (make sure you have your service account key file)
// admin.initializeApp({
//   credential: admin.credential.cert(require('./path/to/serviceAccountKey.json')),
// });

/**
 * Save FCM token for a user
 * POST /users/fcm-token
 */
router.post('/fcm-token', async (req, res) => {
  try {
    const userId = req.user.id; // From auth middleware
    const { token } = req.body;

    if (!token) {
      return res.status(400).json({ error: 'FCM token is required' });
    }

    // Save token to database
    await saveUserFCMToken(userId, token);

    console.log(`✅ FCM token saved for user ${userId}`);
    res.json({ success: true, message: 'FCM token saved' });
  } catch (error) {
    console.error('Error saving FCM token:', error);
    res.status(500).json({ error: 'Failed to save FCM token' });
  }
});

/**
 * Save user's FCM token to database
 */
async function saveUserFCMToken(userId, token) {
  // Example using MongoDB
  // const db = await getDatabase();
  // await db.collection('users').updateOne(
  //   { _id: userId },
  //   { $set: { fcmToken: token, updatedAt: new Date() } }
  // );

  // Or using SQL
  // const query = 'UPDATE users SET fcm_token = ? WHERE id = ?';
  // await db.query(query, [token, userId]);
}

/**
 * Get user's FCM token
 */
async function getUserFCMToken(userId) {
  // Example using MongoDB
  // const db = await getDatabase();
  // const user = await db.collection('users').findOne({ _id: userId });
  // return user?.fcmToken;

  // Or using SQL
  // const query = 'SELECT fcm_token FROM users WHERE id = ?';
  // const result = await db.query(query, [userId]);
  // return result[0]?.fcm_token;
}

/**
 * Send notification to a user
 */
async function sendNotificationToUser(userId, title, body, data = {}) {
  try {
    const userToken = await getUserFCMToken(userId);

    if (!userToken) {
      console.log(`⚠️ No FCM token for user ${userId}`);
      return false;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: data,
      token: userToken,
      // Android-specific options
      android: {
        priority: 'high',
        ttl: 3600, // 1 hour
        notification: {
          sound: 'default',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      // iOS-specific options
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log(`✅ Notification sent to user ${userId}: ${response}`);
    return true;
  } catch (error) {
    console.error(`❌ Error sending notification to user ${userId}:`, error);
    return false;
  }
}

/**
 * Send notification to multiple users
 */
async function sendNotificationToMultipleUsers(userIds, title, body, data = {}) {
  try {
    const tokens = [];
    for (const userId of userIds) {
      const token = await getUserFCMToken(userId);
      if (token) {
        tokens.push(token);
      }
    }

    if (tokens.length === 0) {
      console.log(`⚠️ No FCM tokens found for ${userIds.length} users`);
      return;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: data,
      android: {
        priority: 'high',
      },
    };

    const response = await admin.messaging().sendMulticast({
      ...message,
      tokens: tokens,
    });

    console.log(`✅ Notification sent to ${response.successCount} users`);
    if (response.failureCount > 0) {
      console.log(`⚠️ Failed to send to ${response.failureCount} users`);
      // Handle failures - remove invalid tokens
      response.responses.forEach((resp, index) => {
        if (!resp.success) {
          console.log(`   Failed for token: ${tokens[index]}`);
        }
      });
    }
  } catch (error) {
    console.error('Error sending multi-cast notification:', error);
  }
}

// ==============================================
// TRIGGER NOTIFICATIONS ON EXISTING API CALLS
// ==============================================

/**
 * Example 1: Send notification when a new message is sent
 * Integrate this into your POST /messages endpoint
 */
async function onNewMessage(senderUserId, recipientUserId, message) {
  try {
    const senderName = await getUserName(senderUserId);
    const preview = message.content.substring(0, 50);

    await sendNotificationToUser(
      recipientUserId,
      'New Message',
      `${senderName}: ${preview}${preview.length >= 50 ? '...' : ''}`,
      {
        type: 'chat',
        senderId: senderUserId.toString(),
        messageId: message.id.toString(),
      }
    );

    console.log(`📬 Chat notification sent to user ${recipientUserId}`);
  } catch (error) {
    console.error('Error sending message notification:', error);
  }
}

/**
 * Example 2: Send notification when post is liked
 * Integrate this into your POST /posts/:postId/like endpoint
 */
async function onPostLiked(postOwnerId, likerUserId, postId) {
  try {
    const likerName = await getUserName(likerUserId);

    await sendNotificationToUser(
      postOwnerId,
      '❤️ Your post was liked',
      `${likerName} liked your post`,
      {
        type: 'like',
        postId: postId.toString(),
        userId: likerUserId.toString(),
      }
    );

    console.log(`❤️ Like notification sent to user ${postOwnerId}`);
  } catch (error) {
    console.error('Error sending like notification:', error);
  }
}

/**
 * Example 3: Send notification on new comment
 * Integrate this into your POST /posts/:postId/comments endpoint
 */
async function onPostCommented(postOwnerId, commenterUserId, postId, commentContent) {
  try {
    const commenterName = await getUserName(commenterUserId);
    const preview = commentContent.substring(0, 50);

    await sendNotificationToUser(
      postOwnerId,
      '💬 New comment on your post',
      `${commenterName}: ${preview}${preview.length >= 50 ? '...' : ''}`,
      {
        type: 'comment',
        postId: postId.toString(),
        userId: commenterUserId.toString(),
      }
    );

    console.log(`💬 Comment notification sent to user ${postOwnerId}`);
  } catch (error) {
    console.error('Error sending comment notification:', error);
  }
}

/**
 * Example 4: Send notification on mention
 * Integrate this into your mention detection logic
 */
async function onUserMentioned(mentionedUserIds, mentionerUserId, postId, postContent) {
  try {
    const mentionerName = await getUserName(mentionedUserIds[0]);
    const preview = postContent.substring(0, 50);

    await sendNotificationToMultipleUsers(
      mentionedUserIds,
      '@ You were mentioned',
      `${mentionerName} mentioned you`,
      {
        type: 'mention',
        postId: postId.toString(),
        userId: mentionedUserIds[0].toString(),
      }
    );

    console.log(`@ Mention notification sent to ${mentionedUserIds.length} users`);
  } catch (error) {
    console.error('Error sending mention notification:', error);
  }
}

/**
 * Example 5: Send notification on follow
 * Integrate this into your POST /users/:userId/follow endpoint
 */
async function onUserFollowed(followedUserId, followerUserId) {
  try {
    const followerName = await getUserName(followerUserId);

    await sendNotificationToUser(
      followedUserId,
      '👤 New follower',
      `${followerName} started following you`,
      {
        type: 'follow',
        userId: followerUserId.toString(),
      }
    );

    console.log(`👤 Follow notification sent to user ${followedUserId}`);
  } catch (error) {
    console.error('Error sending follow notification:', error);
  }
}

/**
 * Example 6: Send notification on incoming call
 * Integrate this into your call signaling endpoint
 */
async function onIncomingCall(recipientUserId, callerUserId, channelId) {
  try {
    const callerName = await getUserName(callerUserId);

    await sendNotificationToUser(
      recipientUserId,
      '📞 Incoming Call',
      `${callerName} is calling...`,
      {
        type: 'call',
        callerId: callerUserId.toString(),
        channelId: channelId,
        action: 'INCOMING_CALL',
      }
    );

    console.log(`📞 Call notification sent to user ${recipientUserId}`);
  } catch (error) {
    console.error('Error sending call notification:', error);
  }
}

// Helper function - get user name
async function getUserName(userId) {
  // Implement based on your database
  // Example:
  // const user = await db.collection('users').findOne({ _id: userId });
  // return user?.username || 'Someone';
  return 'User'; // Placeholder
}

// Export functions for use in other files
module.exports = {
  sendNotificationToUser,
  sendNotificationToMultipleUsers,
  onNewMessage,
  onPostLiked,
  onPostCommented,
  onUserMentioned,
  onUserFollowed,
  onIncomingCall,
};
