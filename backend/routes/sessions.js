const express = require("express");
const Session = require("../models/Session");
const trees = require("../config/trees");
const authenticate = require("../middleware/auth");
const notify = require("../utils/notify");

const router = express.Router();

// Save a focus session
router.post("/", authenticate, async (req, res) => {
  try {
    const { durationMinutes, status, treeId } = req.body;

    if (!Number.isInteger(durationMinutes) || durationMinutes < 1 || durationMinutes > 180) {
      return res.status(400).json({ message: "Duration must be a whole number between 1 and 180." });
    }
    if (!["completed", "withered"].includes(status)) {
      return res.status(400).json({ message: "Status must be completed or withered." });
    }

    // only allow tree styles the user really owns
    const okTree = trees.some((t) => t.id === treeId) && req.user.unlockedTrees.includes(treeId);
    const coinsEarned = status === "completed" ? durationMinutes : 0;

    const session = await Session.create({
      user: req.user._id,
      durationMinutes,
      status,
      coinsEarned,
      treeId: okTree ? treeId : "teal",
    });

    if (coinsEarned > 0) {
      req.user.coins += coinsEarned;
      await req.user.save();
    }

    // notifications
    if (status === "completed") {
      await notify(
        req.user,
        "completed",
        "Tree fully grown 🌳",
        `You focused for ${durationMinutes} min and earned ${coinsEarned} coins.`
      );
      const done = await Session.countDocuments({ user: req.user._id, status: "completed" });
      if (done === 1 || done % 10 === 0) {
        await notify(
          req.user,
          "milestone",
          "Milestone reached 🎉",
          done === 1 ? "You grew your very first tree!" : `${done} trees grown. Your forest keeps growing!`
        );
      }
    } else {
      await notify(req.user, "withered", "Your tree withered 🥀", "You left before the timer finished. Try again!");
    }

    return res.status(201).json({
      message: "Focus session saved successfully!",
      session: {
        id: session._id,
        durationMinutes: session.durationMinutes,
        status: session.status,
        coinsEarned: session.coinsEarned,
        treeId: session.treeId,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
      },
      totalCoins: req.user.coins,
    });
  } catch (error) {
    console.error("Save session error:", error.message);
    return res.status(500).json({ message: "Could not save focus session." });
  }
});

// Get the logged-in user's focus sessions (newest first)
router.get("/", authenticate, async (req, res) => {
  try {
    const sessions = await Session.find({ user: req.user._id }).sort({ createdAt: -1 });
    return res.json({ sessions, totalCoins: req.user.coins });
  } catch (error) {
    console.error("Get sessions error:", error.message);
    return res.status(500).json({ message: "Could not load focus sessions." });
  }
});

module.exports = router;