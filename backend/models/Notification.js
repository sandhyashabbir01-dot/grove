const mongoose = require("mongoose");

const notificationSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, index: true },
    type: {
      type: String,
      enum: ["welcome", "completed", "withered", "shop", "milestone", "achievement", "friend_request", "friend_accepted"],
      default: "welcome",
    },
    title: { type: String, required: true },
    body: { type: String, default: "" },
    read: { type: Boolean, default: false },
  },
  { timestamps: true }
);

module.exports = mongoose.models.Notification || mongoose.model("Notification", notificationSchema);