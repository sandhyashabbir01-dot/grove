const express = require("express");
const Session = require("../models/Session");
const trees = require("../config/trees");
const authenticate = require("../middleware/auth");
const notify = require("../utils/notify");

const router = express.Router();

const DAILY_COIN_CAP_MINUTES = 720; // max 12 hours of rewarded focus per rolling 24 h

// Save a focus session
router.post("/", authenticate, async (req, res) => {
  try {
    const { durationMinutes, status, treeId } = req.body;
    const tagIn = typeof req.body.tag === "string" ? req.body.tag.trim() : "";
    const userTags = req.user.tags && req.user.tags.length ? req.user.tags : [];
    const tag = tagIn && tagIn.length <= 30 ? tagIn : userTags[0] || "Study";

    if (!Number.isInteger(durationMinutes) || durationMinutes < 1 || durationMinutes > 180) {
      return res.status(400).json({ message: "Duration must be a whole number between 1 and 180." });
    }
    if (!["completed", "withered"].includes(status)) {
      return res.status(400).json({ message: "Status must be completed or withered." });
    }

    // the app sends when the session started (optional, older versions do not)
    let startedAt = new Date();
    let verified = false;
    if (req.body.startedAt) {
      const t = new Date(req.body.startedAt);
      const now = Date.now();
      if (!Number.isNaN(t.getTime()) && t.getTime() <= now + 60 * 1000 && t.getTime() >= now - 5 * 60 * 60 * 1000) {
        startedAt = t;
        verified = true;
      }
    }

    // a finished tree needs the full time to have passed (90 s tolerance for clock differences)
    if (status === "completed" && verified) {
      const elapsed = (Date.now() - startedAt.getTime()) / 1000;
      if (elapsed < durationMinutes * 60 - 90) {
        return res.status(400).json({ message: "This session was not long enough to finish a tree." });
      }
    }

    // only allow tree styles the user really owns
    const okTree = trees.some((t) => t.id === treeId) && req.user.unlockedTrees.includes(treeId);

    let coinsEarned = status === "completed" ? durationMinutes : 0;
    if (coinsEarned > 0) {
      const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const recent = await Session.aggregate([
        { $match: { user: req.user._id, status: "completed", createdAt: { $gte: since } } },
        { $group: { _id: null, minutes: { $sum: "$durationMinutes" } } },
      ]);
      const used = recent.length ? recent[0].minutes : 0;
      if (used + durationMinutes > DAILY_COIN_CAP_MINUTES) coinsEarned = 0;
    }

    const session = await Session.create({
      user: req.user._id,
      durationMinutes,
      status,
      coinsEarned,
      treeId: okTree ? treeId : "teal",
      tag,
      startedAt,
      endedAt: new Date(),
    });

    if (coinsEarned > 0) {
      req.user.coins += coinsEarned;
      await req.user.save();
    }

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
        tag: session.tag,
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
    const sessions = await Session.find({ user: req.user._id }).sort({ startedAt: -1 }).limit(1000);
    return res.json({ sessions, totalCoins: req.user.coins });
  } catch (error) {
    console.error("Get sessions error:", error.message);
    return res.status(500).json({ message: "Could not load focus sessions." });
  }
});

module.exports = router;