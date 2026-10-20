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

    // settings / Time Guard / goals
    tags: {
      type: [String],
      default: ["Study", "Work", "Sport", "Rest", "Social", "Entertainment", "Other"],
    },
    whitelistApps: { type: [String], default: [] },
    graceSeconds: { type: Number, default: 0, min: 0, max: 60 },
    dailyGoal: { type: Number, default: 60, min: 10, max: 600 },

    // social / rewards
    friends: [{ type: mongoose.Schema.Types.ObjectId, ref: "User" }],
    friendRequests: [{ type: mongoose.Schema.Types.ObjectId, ref: "User" }],
    achievementsSeen: { type: [String], default: [] },
    claimedChallenges: { type: [String], default: [] }, // e.g. "daily_30:2026-10-17"
    realTrees: { type: Number, default: 0, min: 0 },

    // Grove Gold / Business
    subscriptionStatus: { type: String, enum: ["free", "active", "past_due", "cancelled"], default: "free" },
    subscriptionPlan: { type: String, enum: ["none", "monthly", "yearly", "business"], default: "none" },
    stripeCustomerId: { type: String, default: null },
    stripeSubscriptionId: { type: String, default: null },
    subscriptionPeriodEnd: { type: Date, default: null },
  },
  { timestamps: true }
);

module.exports = mongoose.models.User || mongoose.model("User", userSchema);