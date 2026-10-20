const mongoose = require("mongoose");

const focusRoomSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 50 },
    code: { type: String, required: true, unique: true, uppercase: true, index: true },
    host: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    members: [
      {
        user: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
        joinedAt: { type: Date, default: Date.now },
        state: { type: String, enum: ["ready", "gaveup"], default: "ready" },
      },
    ],
    // waiting -> focusing -> finished (everyone stayed)  or  failed (somebody gave up)
    status: { type: String, enum: ["waiting", "focusing", "finished", "failed"], default: "waiting" },
    failedBy: { type: String, default: "" },
    durationMinutes: { type: Number, default: 25, min: 1, max: 180 },
    startedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

// rooms disappear by themselves after 24 hours
focusRoomSchema.index({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 });

module.exports = mongoose.models.FocusRoom || mongoose.model("FocusRoom", focusRoomSchema);