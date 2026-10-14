// "Continue with Google" using the standard OAuth redirect flow (no extra npm packages)
const express = require("express");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const { OAuth2Client } = require("google-auth-library");
const User = require("../models/User");
const publicUser = require("../utils/publicUser");
const notify = require("../utils/notify");

const router = express.Router();

const clean = (v) => (v || "").replace(/\/$/, "");
const redirectUri = () => `${clean(process.env.BACKEND_URL)}/api/auth/google/callback`;
const configured = () =>
  process.env.GOOGLE_CLIENT_ID &&
  process.env.GOOGLE_CLIENT_SECRET &&
  process.env.BACKEND_URL &&
  process.env.FRONTEND_URL &&
  process.env.JWT_SECRET;

// Step 1: send the browser to Google
router.get("/google", (req, res) => {
  if (!configured()) return res.status(500).send("Google login is not configured on the server.");
  const state = jwt.sign({ purpose: "oauth", n: crypto.randomBytes(8).toString("hex") }, process.env.JWT_SECRET, {
    expiresIn: "10m",
  });
  const params = new URLSearchParams({
    client_id: process.env.GOOGLE_CLIENT_ID,
    redirect_uri: redirectUri(),
    response_type: "code",
    scope: "openid email profile",
    state,
    prompt: "select_account",
  });
  res.redirect("https://accounts.google.com/o/oauth2/v2/auth?" + params.toString());
});

// Step 2: Google sends the browser back here with a code
router.get("/google/callback", async (req, res) => {
  const back = (q) => res.redirect(`${clean(process.env.FRONTEND_URL)}/?${q}`);
  try {
    if (!configured()) throw new Error("not configured");
    const { code, state, error } = req.query;
    if (error) return back("google_error=" + encodeURIComponent(String(error)));

    const st = jwt.verify(String(state), process.env.JWT_SECRET);
    if (st.purpose !== "oauth") throw new Error("bad state");

    const tr = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code: String(code),
        client_id: process.env.GOOGLE_CLIENT_ID,
        client_secret: process.env.GOOGLE_CLIENT_SECRET,
        redirect_uri: redirectUri(),
        grant_type: "authorization_code",
      }),
    });
    const tj = await tr.json();
    if (!tr.ok || !tj.id_token) throw new Error(tj.error_description || "token exchange failed");

   
    const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

    const googleTicket = await googleClient.verifyIdToken({
      idToken: tj.id_token,
      audience: process.env.GOOGLE_CLIENT_ID,
    });

    const payload = googleTicket.getPayload();

    if (!payload || !payload.sub || !payload.email || payload.email_verified !== true) {
      throw new Error("Invalid or unverified Google account");
    }


    const email = payload.email.toLowerCase();
    let user = await User.findOne({ email });
    if (!user) {
      user = await User.create({
        name: payload.name || email.split("@")[0],
        email,
        passwordHash: crypto.randomBytes(32).toString("hex"), // google users have no password
        provider: "google",
        googleId: payload.sub,
      });
      await notify(user, "welcome", "Welcome to Grove! 🌳", "Plant your first tree and start focusing.");
    } else if (!user.googleId) {
      user.googleId = payload.sub;
      await user.save();
    }

    // short-lived one-time-ish ticket; the app swaps it for a real login token
    const ticket = jwt.sign({ purpose: "ticket", userId: user._id.toString() }, process.env.JWT_SECRET, {
      expiresIn: "90s",
    });
    return back("ticket=" + encodeURIComponent(ticket));
  } catch (e) {
    console.error("Google callback error:", e.message);
    return back("google_error=failed");
  }
});

// Step 3: the app exchanges the ticket for a normal login token
router.post("/exchange", async (req, res) => {
  try {
    const decoded = jwt.verify(String(req.body.ticket), process.env.JWT_SECRET);
    if (decoded.purpose !== "ticket") throw new Error("bad ticket");
    const user = await User.findById(decoded.userId);
    if (!user) throw new Error("no user");
    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET, { expiresIn: "7d" });
    res.json({ message: "Login successful!", token, user: publicUser(user) });
  } catch (e) {
    res.status(401).json({ message: "Google login expired. Please try again." });
  }
});

module.exports = router;