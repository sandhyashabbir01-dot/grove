
const mongoose = require("mongoose");

const journalEntrySchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
      maxlength: 100,
    },
    body: {
      type: String,
      required: true,
      maxlength: 5000,
    },
    mood: {
      type: String,
      enum: ["calm", "focused", "happy", "tired", "stressed"],
      default: "focused",
    },
  },
  { timestamps: true }
);

module.exports =
  mongoose.models.JournalEntry ||
  mongoose.model("JournalEntry", journalEntrySchema);
