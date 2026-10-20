
require("dotenv").config();

const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");

const app = express();
app.use(cors());

let connecting = null;

async function connectDB() {
  if (mongoose.connection.readyState === 1) return;

  if (!process.env.MONGODB_URI) {
    throw new Error("MONGODB_URI is missing");
  }

  if (!connecting) {
    connecting = mongoose.connect(process.env.MONGODB_URI, {
      serverSelectionTimeoutMS: 8000,
    });
  }

  try {
    await connecting;
  } catch (error) {
    connecting = null;
    throw error;
  }
}

app.use(async (req, res, next) => {
  try {
    await connectDB();
    next();
  } catch (error) {
    console.error("Database error:", error.message);
    res.status(500).json({
      message: "Database connection failed.",
    });
  }
});

// Stripe webhook must receive the raw body before express.json().
app.post(
  "/api/billing/webhook",
  express.raw({ type: "application/json" }),
  (req, res) => require("./routes/billing").webhook(req, res)
);

app.use(express.json({ limit: "1mb" }));

app.get("/", (req, res) => {
  res.json({ message: "Grove backend is running successfully!" });
});

app.use("/api/auth", require("./routes/auth"));
app.use("/api/auth", require("./routes/google"));
app.use("/api/notifications", require("./routes/notifications"));
app.use("/api/sessions", require("./routes/sessions"));
app.use("/api/shop", require("./routes/shop"));
app.use("/api/friends", require("./routes/friends"));
app.use("/api/achievements", require("./routes/achievements"));
app.use("/api/settings", require("./routes/settings"));

// Grove feature routes
app.use("/api/rooms", require("./routes/rooms"));
app.use("/api/teams", require("./routes/teams"));
app.use("/api/journal", require("./routes/journal"));
app.use("/api/challenges", require("./routes/challenges"));
app.use("/api/billing", require("./routes/billing"));
app.use("/api/leaderboard", require("./routes/leaderboard"));

module.exports = app;

if (require.main === module) {
  const PORT = process.env.PORT || 5000;
  app.listen(PORT, () => {
    console.log(`Grove backend running on port ${PORT}`);
  });
}
