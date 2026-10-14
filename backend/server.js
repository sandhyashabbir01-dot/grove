require("dotenv").config();

const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json());

// Connect to MongoDB once and reuse the connection (needed for Vercel serverless)
let connecting = null;
async function connectDB() {
  if (mongoose.connection.readyState === 1) return;
  if (!process.env.MONGODB_URI) throw new Error("MONGODB_URI is missing");
  if (!connecting) {
    connecting = mongoose.connect(process.env.MONGODB_URI, {
      serverSelectionTimeoutMS: 8000,
    });
  }
  try {
    await connecting;
  } catch (e) {
    connecting = null;
    throw e;
  }
}

app.use(async (req, res, next) => {
  try {
    await connectDB();
    next();
  } catch (e) {
    console.error("Database error:", e.message);
    res.status(500).json({ message: "Database connection failed." });
  }
});

app.get("/", (req, res) => {
  res.json({ message: "Grove backend is running successfully!" });
});

app.use("/api/auth", require("./routes/auth"));
app.use("/api/auth", require("./routes/google"));
app.use("/api/notifications", require("./routes/notifications"));
app.use("/api/sessions", require("./routes/sessions"));
app.use("/api/shop", require("./routes/shop"));

module.exports = app;

// Local run:  node server.js   (on Vercel the app is exported, not started)
if (require.main === module) {
  const PORT = process.env.PORT || 5000;
  app.listen(PORT, () => console.log(`Grove backend running at http://localhost:${PORT}`));
}