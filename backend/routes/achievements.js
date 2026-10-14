const express = require("express");
const authenticate = require("../middleware/auth");
const { sync } = require("../lib/achievements");

const router = express.Router();

router.get("/", authenticate, async (req, res) => {
  try {
    const { list } = await sync(req.user);
    res.json({ achievements: list });
  } catch (error) {
    console.error("Achievements error:", error.message);
    res.status(500).json({ message: "Could not load achievements." });
  }
});

module.exports = router;