const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const User = require("../models/User");
const Notification = require("../models/Notification");
const authenticate = require("../middleware/auth");
const publicUser = require("../utils/publicUser");
const notify = require("../utils/notify");

const router = express.Router();

// REGISTER
router.post("/register", async (req, res) => {
  try {
    const { name, email, password } = req.body;

    if (
      typeof name !== "string" ||
      typeof email !== "string" ||
      typeof password !== "string" ||
      !name.trim() ||
      !email.trim() ||
      !password
    ) {
      return res.status(400).json({ message: "Name, email and password are required." });
    }
    if (password.length < 8) {
      return res.status(400).json({ message: "Password must be at least 8 characters." });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const existingUser = await User.findOne({ email: normalizedEmail });
    if (existingUser) {
      return res.status(409).json({ message: "An account with this email already exists." });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const user = await User.create({ name: name.trim(), email: normalizedEmail, passwordHash });
    await notify(user, "welcome", "Welcome to Grove! 🌳", "Plant your first tree and start focusing.");

    return res.status(201).json({ message: "Registration successful!", user: publicUser(user) });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(409).json({ message: "An account with this email already exists." });
    }
    console.error("Registration error:", error.message);
    return res.status(500).json({ message: "Registration failed. Please try again." });
  }
});

// LOGIN
router.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    if (typeof email !== "string" || typeof password !== "string" || !email.trim() || !password) {
      return res.status(400).json({ message: "Email and password are required." });
    }

    const user = await User.findOne({ email: email.trim().toLowerCase() });
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      return res.status(401).json({ message: "Invalid email or password." });
    }
    if (!process.env.JWT_SECRET) {
      console.error("JWT_SECRET is missing");
      return res.status(500).json({ message: "Authentication is not configured." });
    }

    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET, { expiresIn: "7d" });

    return res.json({ message: "Login successful!", token, user: publicUser(user) });
  } catch (error) {
    console.error("Login error:", error.message);
    return res.status(500).json({ message: "Login failed. Please try again." });
  }
});

// WHO AM I (auto-login, refresh coins and the unread-notification badge)
router.get("/me", authenticate, async (req, res) => {
  try {
    const unread = await Notification.countDocuments({ user: req.user._id, read: false });
    res.json({ user: { ...publicUser(req.user), unread } });
  } catch (e) {
    console.error("Me error:", e.message);
    res.status(500).json({ message: "Could not load your profile." });
  }
});

// SETTINGS (notifications on/off)
router.patch("/settings", authenticate, async (req, res) => {
  try {
    if (typeof req.body.notificationsEnabled === "boolean") {
      req.user.notificationsEnabled = req.body.notificationsEnabled;
      await req.user.save();
    }
    res.json({ user: publicUser(req.user) });
  } catch (e) {
    console.error("Settings error:", e.message);
    res.status(500).json({ message: "Could not save settings." });
  }
});

module.exports = router;