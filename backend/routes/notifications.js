const express = require("express");
const Notification = require("../models/Notification");
const authenticate = require("../middleware/auth");

const router = express.Router();

// List my notifications (newest first) + unread count
router.get("/", authenticate, async (req, res) => {
  try {
    const notifications = await Notification.find({ user: req.user._id }).sort({ createdAt: -1 }).limit(50);
    const unread = await Notification.countDocuments({ user: req.user._id, read: false });
    res.json({ notifications, unread });
  } catch (e) {
    console.error("List notifications error:", e.message);
    res.status(500).json({ message: "Could not load notifications." });
  }
});

// Mark all as read
router.post("/read-all", authenticate, async (req, res) => {
  try {
    await Notification.updateMany({ user: req.user._id, read: false }, { read: true });
    res.json({ unread: 0 });
  } catch (e) {
    console.error("Read-all error:", e.message);
    res.status(500).json({ message: "Could not update notifications." });
  }
});

// Delete all
router.delete("/", authenticate, async (req, res) => {
  try {
    await Notification.deleteMany({ user: req.user._id });
    res.json({ unread: 0 });
  } catch (e) {
    console.error("Clear notifications error:", e.message);
    res.status(500).json({ message: "Could not clear notifications." });
  }
});

module.exports = router;