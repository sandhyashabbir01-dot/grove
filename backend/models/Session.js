const mongoose = require("mongoose");

const sessionSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, index: true },
    durationMinutes: { type: Number, required: true, min: 1, max: 180 },
    status: { type: String, enum: ["completed", "withered"], required: true },
    coinsEarned: { type: Number, default: 0, min: 0 },
    treeId: { type: String, default: "teal" },
    startedAt: { type: Date, default: Date.now },
    endedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

module.exports = mongoose.models.Session || mongoose.model("Session", sessionSchema);