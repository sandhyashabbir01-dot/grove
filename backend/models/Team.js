
const mongoose = require("mongoose");

const teamSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
      maxlength: 70,
    },
    code: {
      type: String,
      required: true,
      unique: true,
      index: true,
    },
    owner: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    members: [{
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
    }],
    plan: {
      type: String,
      enum: ["free", "business"],
      default: "free",
    },
  },
  { timestamps: true }
);

module.exports =
  mongoose.models.Team || mongoose.model("Team", teamSchema);
