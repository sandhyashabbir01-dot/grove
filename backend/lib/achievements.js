const Session = require("../models/Session");
const Notification = require("../models/Notification");
const trees = require("../config/trees");

const dayKey = (d) => new Date(d).toISOString().slice(0, 10); // UTC day

function longestStreak(dates) {
  const days = [...new Set(dates.map(dayKey))].sort();
  let best = 0;
  let run = 0;
  let prev = null;
  for (const d of days) {
    if (prev && (new Date(d) - new Date(prev)) / 86400000 === 1) run += 1;
    else run = 1;
    best = Math.max(best, run);
    prev = d;
  }
  return best;
}

// Builds the achievement list (with progress) from the user + their sessions
function compute(user, sessions) {
  const ok = sessions.filter((s) => s.status === "completed");
  const minutes = ok.reduce((a, s) => a + s.durationMinutes, 0);
  const longest = ok.reduce((a, s) => Math.max(a, s.durationMinutes), 0);
  const streak = longestStreak(ok.map((s) => s.startedAt));
  const owned = (user.unlockedTrees || []).length;

  const defs = [
    { id: "first_tree", icon: "🌱", title: "First Seed", description: "Grow your first tree", value: ok.length, target: 1 },
    { id: "trees_10", icon: "🌳", title: "Little Grove", description: "Grow 10 trees", value: ok.length, target: 10 },
    { id: "trees_50", icon: "🌲", title: "Forest Keeper", description: "Grow 50 trees", value: ok.length, target: 50 },
    { id: "trees_100", icon: "🏞️", title: "Woodland Hero", description: "Grow 100 trees", value: ok.length, target: 100 },
    { id: "minutes_100", icon: "⏱️", title: "Focused", description: "Focus for 100 minutes in total", value: minutes, target: 100 },
    { id: "minutes_1000", icon: "🔥", title: "Deep Work", description: "Focus for 1000 minutes in total", value: minutes, target: 1000 },
    { id: "long_focus", icon: "🧘", title: "Marathon", description: "Finish a 60 minute session", value: longest, target: 60 },
    { id: "streak_3", icon: "📅", title: "On a Roll", description: "Focus 3 days in a row", value: streak, target: 3 },
    { id: "streak_7", icon: "🏆", title: "Perfect Week", description: "Focus 7 days in a row", value: streak, target: 7 },
    { id: "collector", icon: "🎨", title: "Collector", description: "Unlock every tree style", value: owned, target: trees.length },
    { id: "friend", icon: "🤝", title: "Better Together", description: "Make your first friend", value: (user.friends || []).length, target: 1 },
    { id: "real_tree", icon: "🌍", title: "Real Impact", description: "Request a real tree", value: user.realTrees || 0, target: 1 },
  ];

  return defs.map((d) => ({
    ...d,
    value: Math.min(d.value, d.target),
    unlocked: d.value >= d.target,
  }));
}

// Computes achievements, notifies the user about NEW ones (once), returns { list, fresh }
async function sync(user) {
  const sessions = await Session.find({ user: user._id }).select("durationMinutes status startedAt").lean();
  const list = compute(user, sessions);
  const seen = new Set(user.achievementsSeen || []);
  const fresh = list.filter((a) => a.unlocked && !seen.has(a.id));
  if (fresh.length) {
    user.achievementsSeen = [...seen, ...fresh.map((a) => a.id)];
    await user.save();
    await Notification.insertMany(
      fresh.map((a) => ({
        user: user._id,
        type: "achievement",
        title: `Achievement unlocked: ${a.title}`,
        body: a.description,
      }))
    );
  }
  return { list, fresh };
}

module.exports = { compute, sync };