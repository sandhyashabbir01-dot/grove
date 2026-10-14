const express = require("express");
const mongoose = require("mongoose");
const User = require("../models/User");
const Session = require("../models/Session");
const Notification = require("../models/Notification");
const authenticate = require("../middleware/auth");
const { sync } = require("../lib/achievements");

const router = express.Router();
const same = (a, b) => String(a) === String(b);
const has = (list, id) => list.some((x) => same(x, id));

// You + your friends ranked by total focus minutes
async function leaderboard(me) {
  const ids = [me._id, ...me.friends];
  const totals = await Session.aggregate([
    { $match: { user: { $in: ids }, status: "completed" } },
    { $group: { _id: "$user", minutes: { $sum: "$durationMinutes" }, trees: { $sum: 1 } } },
  ]);
  const byUser = new Map(totals.map((t) => [String(t._id), t]));
  const users = await User.find({ _id: { $in: ids } }).select("name email coins");
  return users
    .map((u) => {
      const t = byUser.get(String(u._id)) || { minutes: 0, trees: 0 };
      return {
        id: u._id,
        name: u.name,
        email: u.email,
        coins: u.coins,
        minutes: t.minutes,
        trees: t.trees,
        isMe: same(u._id, me._id),
      };
    })
    .sort((a, b) => b.minutes - a.minutes);
}

async function makeFriends(me, other) {
  me.friendRequests = me.friendRequests.filter((f) => !same(f, other._id));
  other.friendRequests = other.friendRequests.filter((f) => !same(f, me._id));
  if (!has(me.friends, other._id)) me.friends.push(other._id);
  if (!has(other.friends, me._id)) other.friends.push(me._id);
  await me.save();
  await other.save();
  await Notification.create({
    user: other._id,
    type: "friend_accepted",
    title: "Friend request accepted 🤝",
    body: `${me.name} is now your friend.`,
  });
  await sync(me);
  await sync(other);
}

// Friends leaderboard + incoming requests
router.get("/", authenticate, async (req, res) => {
  try {
    const requests = await User.find({ _id: { $in: req.user.friendRequests } }).select("name email");
    res.json({
      leaderboard: await leaderboard(req.user),
      requests: requests.map((u) => ({ id: u._id, name: u.name, email: u.email })),
    });
  } catch (error) {
    console.error("Friends error:", error.message);
    res.status(500).json({ message: "Could not load friends." });
  }
});

// Send a friend request by email
router.post("/request", authenticate, async (req, res) => {
  try {
    const email = typeof req.body.email === "string" ? req.body.email.trim().toLowerCase() : "";
    if (!email) return res.status(400).json({ message: "Please enter your friend's email." });

    const target = await User.findOne({ email });
    if (!target) return res.status(404).json({ message: "No Grove user found with this email." });
    if (same(target._id, req.user._id)) return res.status(400).json({ message: "You can't add yourself." });
    if (has(req.user.friends, target._id)) return res.status(409).json({ message: "You are already friends." });

    // they already asked us -> just accept
    if (has(req.user.friendRequests, target._id)) {
      await makeFriends(req.user, target);
      return res.json({ message: `You and ${target.name} are now friends!` });
    }
    if (has(target.friendRequests, req.user._id)) {
      return res.status(409).json({ message: "Friend request already sent." });
    }

    target.friendRequests.push(req.user._id);
    await target.save();
    await Notification.create({
      user: target._id,
      type: "friend_request",
      title: "New friend request",
      body: `${req.user.name} wants to be your friend.`,
    });
    return res.status(201).json({ message: `Friend request sent to ${target.name}.` });
  } catch (error) {
    console.error("Friend request error:", error.message);
    return res.status(500).json({ message: "Could not send the friend request." });
  }
});

// Accept a request
router.post("/accept", authenticate, async (req, res) => {
  try {
    const { userId } = req.body;
    if (!mongoose.isValidObjectId(userId) || !has(req.user.friendRequests, userId)) {
      return res.status(400).json({ message: "No such friend request." });
    }
    const other = await User.findById(userId);
    if (!other) return res.status(404).json({ message: "User not found." });
    await makeFriends(req.user, other);
    return res.json({ message: `You and ${other.name} are now friends!` });
  } catch (error) {
    console.error("Accept error:", error.message);
    return res.status(500).json({ message: "Could not accept the request." });
  }
});

// Reject a request
router.post("/reject", authenticate, async (req, res) => {
  try {
    const { userId } = req.body;
    if (!mongoose.isValidObjectId(userId)) return res.status(400).json({ message: "Invalid user." });
    req.user.friendRequests = req.user.friendRequests.filter((f) => !same(f, userId));
    await req.user.save();
    return res.json({ message: "Request removed." });
  } catch (error) {
    console.error("Reject error:", error.message);
    return res.status(500).json({ message: "Could not reject the request." });
  }
});

// Remove a friend
router.delete("/:id", authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.isValidObjectId(id)) return res.status(400).json({ message: "Invalid user." });
    req.user.friends = req.user.friends.filter((f) => !same(f, id));
    await req.user.save();
    const other = await User.findById(id);
    if (other) {
      other.friends = other.friends.filter((f) => !same(f, req.user._id));
      await other.save();
    }
    return res.json({ message: "Friend removed." });
  } catch (error) {
    console.error("Remove friend error:", error.message);
    return res.status(500).json({ message: "Could not remove the friend." });
  }
});

module.exports = router;