const Notification = require("../models/Notification");

// Creates an in-app notification for a user (skipped if they turned notifications off)
module.exports = async function notify(user, type, title, body) {
  try {
    if (user.notificationsEnabled === false) return;
    await Notification.create({ user: user._id, type, title, body });
  } catch (e) {
    console.error("notify error:", e.message);
  }
};