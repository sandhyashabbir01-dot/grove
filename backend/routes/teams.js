
const express = require("express");
const crypto = require("crypto");
const Team = require("../models/Team");
const Session = require("../models/Session");
const authenticate = require("../middleware/auth");

const router = express.Router();
const makeCode = () => crypto.randomBytes(4).toString("hex").toUpperCase();

router.use(authenticate);

router.get("/", async (req, res) => {
  try {
    const teams = await Team.find({ members: req.user._id })
      .populate("owner", "name")
      .populate("members", "name")
      .sort({ createdAt: -1 });

    res.json({
      teams: teams.map((team) => ({
        id: team.id,
        name: team.name,
        code: team.code,
        plan: team.plan,
        owner: {
          id: String(team.owner._id),
          name: team.owner.name,
        },
        members: team.members.map((member) => ({
          id: String(member._id),
          name: member.name,
        })),
      })),
    });
  } catch {
    res.status(500).json({ message: "Could not load teams." });
  }
});

router.post("/", async (req, res) => {
  try {
    const name = String(req.body.name || "").trim();

    if (!name || name.length > 70) {
      return res.status(400).json({
        message: "Team name is required (maximum 70 characters).",
      });
    }

    let code = makeCode();
    while (await Team.exists({ code })) code = makeCode();

    const team = await Team.create({
      name,
      code,
      owner: req.user._id,
      members: [req.user._id],
    });

    res.status(201).json({
      team: {
        id: team.id,
        name: team.name,
        code: team.code,
        plan: team.plan,
      },
    });
  } catch {
    res.status(500).json({ message: "Could not create team." });
  }
});

router.post("/join", async (req, res) => {
  try {
    const code = String(req.body.code || "").trim().toUpperCase();
    const team = await Team.findOne({ code });

    if (!team) {
      return res.status(404).json({ message: "Team code not found." });
    }

    const alreadyMember = team.members.some(
      (id) => String(id) === String(req.user._id)
    );

    if (!alreadyMember) {
      if (team.members.length >= 50) {
        return res.status(409).json({
          message: "This team is full (50 members maximum).",
        });
      }

      team.members.push(req.user._id);
      await team.save();
    }

    res.json({
      message: "You joined the team.",
      team: { id: team.id, name: team.name, code: team.code },
    });
  } catch {
    res.status(500).json({ message: "Could not join team." });
  }
});

router.get("/:id/leaderboard", async (req, res) => {
  try {
    const team = await Team.findById(req.params.id)
      .populate("members", "name");

    if (!team) {
      return res.status(404).json({ message: "Team not found." });
    }

    const isMember = team.members.some(
      (member) => String(member._id) === String(req.user._id)
    );

    if (!isMember) {
      return res.status(403).json({
        message: "Join this team to view its leaderboard.",
      });
    }

    const ids = team.members.map((member) => member._id);

    const totals = await Session.aggregate([
      {
        $match: {
          user: { $in: ids },
          status: "completed",
        },
      },
      {
        $group: {
          _id: "$user",
          minutes: { $sum: "$durationMinutes" },
          sessions: { $sum: 1 },
        },
      },
    ]);

    const totalsById = new Map(
      totals.map((item) => [String(item._id), item])
    );

    const leaderboard = team.members.map((member) => {
      const total = totalsById.get(String(member._id));

      return {
        id: String(member._id),
        name: member.name,
        minutes: total?.minutes || 0,
        sessions: total?.sessions || 0,
        isMe: String(member._id) === String(req.user._id),
      };
    }).sort((a, b) => b.minutes - a.minutes);

    res.json({
      team: { id: team.id, name: team.name, code: team.code },
      leaderboard,
    });
  } catch {
    res.status(500).json({
      message: "Could not load team leaderboard.",
    });
  }
});

router.delete("/:id/leave", async (req, res) => {
  try {
    const team = await Team.findById(req.params.id);

    if (!team) {
      return res.status(404).json({ message: "Team not found." });
    }

    if (String(team.owner) === String(req.user._id)) {
      return res.status(400).json({
        message:
          "The owner must transfer ownership or delete the team before leaving.",
      });
    }

    team.members = team.members.filter(
      (id) => String(id) !== String(req.user._id)
    );

    await team.save();
    res.json({ message: "Left the team." });
  } catch {
    res.status(500).json({ message: "Could not leave team." });
  }
});

module.exports = router;
