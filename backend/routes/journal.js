
const express = require("express");
const JournalEntry = require("../models/JournalEntry");
const authenticate = require("../middleware/auth");

const router = express.Router();
router.use(authenticate);

router.get("/", async (req, res) => {
  try {
    const entries = await JournalEntry.find({ user: req.user._id })
      .sort({ createdAt: -1 })
      .limit(100)
      .lean();

    res.json({ entries });
  } catch {
    res.status(500).json({ message: "Could not load journal." });
  }
});

router.post("/", async (req, res) => {
  try {
    const title = String(req.body.title || "").trim();
    const body = String(req.body.body || "").trim();
    const mood = String(req.body.mood || "focused");

    if (!title || !body) {
      return res.status(400).json({
        message: "Title and journal text are required.",
      });
    }

    if (title.length > 100 || body.length > 5000) {
      return res.status(400).json({
        message: "Title or entry is too long.",
      });
    }

    const allowedMoods = [
      "calm",
      "focused",
      "happy",
      "tired",
      "stressed",
    ];

    if (!allowedMoods.includes(mood)) {
      return res.status(400).json({ message: "Invalid mood." });
    }

    const entry = await JournalEntry.create({
      user: req.user._id,
      title,
      body,
      mood,
    });

    res.status(201).json({ entry });
  } catch {
    res.status(500).json({
      message: "Could not save journal entry.",
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    const result = await JournalEntry.deleteOne({
      _id: req.params.id,
      user: req.user._id,
    });

    if (!result.deletedCount) {
      return res.status(404).json({
        message: "Journal entry not found.",
      });
    }

    res.json({ message: "Entry deleted." });
  } catch {
    res.status(500).json({
      message: "Could not delete entry.",
    });
  }
});

module.exports = router;
