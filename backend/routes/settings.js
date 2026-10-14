const express = require("express");
const authenticate = require("../middleware/auth");

const router = express.Router();

const PACKAGE_RE = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/; // e.g. com.whatsapp

const view = (u) => ({
  tags: u.tags,
  whitelistApps: u.whitelistApps,
  graceSeconds: u.graceSeconds,
});

router.get("/", authenticate, (req, res) => res.json(view(req.user)));

// Update the app whitelist and / or the grace period
router.put("/", authenticate, async (req, res) => {
  try {
    const { whitelistApps, graceSeconds } = req.body;

    if (whitelistApps !== undefined) {
      if (!Array.isArray(whitelistApps) || whitelistApps.length > 30) {
        return res.status(400).json({ message: "Whitelist must be a list of up to 30 apps." });
      }
      const clean = [...new Set(whitelistApps.map((x) => (typeof x === "string" ? x.trim() : "")))];
      if (clean.some((x) => !PACKAGE_RE.test(x) || x.length > 120)) {
        return res.status(400).json({ message: "Each app must be a valid package name like com.whatsapp." });
      }
      req.user.whitelistApps = clean;
    }
    if (graceSeconds !== undefined) {
      if (!Number.isInteger(graceSeconds) || graceSeconds < 0 || graceSeconds > 60) {
        return res.status(400).json({ message: "Grace period must be between 0 and 60 seconds." });
      }
      req.user.graceSeconds = graceSeconds;
    }
    await req.user.save();
    return res.json(view(req.user));
  } catch (error) {
    console.error("Settings error:", error.message);
    return res.status(500).json({ message: "Could not save settings." });
  }
});

// Add a tag / category
router.post("/tags", authenticate, async (req, res) => {
  try {
    const name = typeof req.body.name === "string" ? req.body.name.trim() : "";
    if (!name || name.length > 30) {
      return res.status(400).json({ message: "Tag name must be 1 to 30 characters." });
    }
    if (req.user.tags.length >= 12) {
      return res.status(400).json({ message: "You can have up to 12 tags." });
    }
    if (req.user.tags.some((t) => t.toLowerCase() === name.toLowerCase())) {
      return res.status(409).json({ message: "This tag already exists." });
    }
    req.user.tags.push(name);
    await req.user.save();
    return res.status(201).json(view(req.user));
  } catch (error) {
    console.error("Add tag error:", error.message);
    return res.status(500).json({ message: "Could not add the tag." });
  }
});

// Delete a tag
router.delete("/tags/:name", authenticate, async (req, res) => {
  try {
    if (req.user.tags.length <= 1) {
      return res.status(400).json({ message: "Keep at least one tag." });
    }
    req.user.tags = req.user.tags.filter((t) => t !== req.params.name);
    await req.user.save();
    return res.json(view(req.user));
  } catch (error) {
    console.error("Delete tag error:", error.message);
    return res.status(500).json({ message: "Could not delete the tag." });
  }
});

module.exports = router;