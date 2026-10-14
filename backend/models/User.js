const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true },
    provider: { type: String, enum: ["email", "google"], default: "email" },
    googleId: { type: String, index: true, sparse: true },
    coins: { type: Number, default: 0, min: 0 },
    unlockedTrees: { type: [String], default: ["teal"] },
    selectedTree: { type: String, default: "teal" },
    notificationsEnabled: { type: Boolean, default: true },
  },
  { timestamps: true }
);

module.exports = mongoose.models.User || mongoose.model("User", userSchema);