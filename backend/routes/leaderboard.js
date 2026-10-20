
const express = require("express");
const User = require("../models/User");
const Session = require("../models/Session");
const authenticate = require("../middleware/auth");

const router = express.Router();

router.get("/", authenticate, async (req, res) => {
  try {
    const allowedPeriods = ["week", "month", "all"];
    const period = allowedPeriods.includes(req.query.period)
      ? req.query.period
      : "week";

    const match = { status: "completed" };

    if (period !== "all") {
      const start = new Date();

      if (period === "week") {
        start.setDate(start.getDate() - 7);
      } else {
        start.setDate(start.getDate() - 30);
      }

      match.startedAt = { $gte: start };
    }

    const totals = await Session.aggregate([
      { $match: match },
      {
        $group: {
          _id: "$user",
          minutes: { $sum: "$durationMinutes" },
          sessions: { $sum: 1 },
          trees: { $sum: 1 },
        },
      },
      { $sort: { minutes: -1 } },
      { $limit: 100 },
    ]);

    const users = await User.find({
      _id: { $in: totals.map((item) => item._id) },
    }).select("name");

    const names = new Map(
      users.map((user) => [String(user._id), user.name])
    );

    const leaderboard = totals.map((item, index) => ({
      rank: index + 1,
      id: String(item._id),
      name: names.get(String(item._id)) || "Grove member",
      minutes: item.minutes,
      sessions: item.sessions,
      trees: item.trees,
      isMe: String(item._id) === String(req.user._id),
    }));

    res.json({
      period,
      leaderboard,
      me: leaderboard.find((item) => item.isMe) || null,
    });
  } catch (error) {
    console.error("Leaderboard error:", error.message);
    res.status(500).json({
      message: "Could not load leaderboard.",
    });
  }
});

module.exports = router;
