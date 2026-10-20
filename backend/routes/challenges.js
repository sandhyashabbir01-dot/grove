const express = require("express");
const Session = require("../models/Session");
const authenticate = require("../middleware/auth");
const notify = require("../utils/notify");

const router = express.Router();
router.use(authenticate);

// ---- day / week keys in the user's own time zone (minutes east of UTC) ----
const shift = (d, tz) => new Date(new Date(d).getTime() + tz * 60000);
const dayKey = (d, tz) => shift(d, tz).toISOString().slice(0, 10);
function weekKey(d, tz) {
  const l = shift(d, tz);
  const dow = (l.getUTCDay() + 6) % 7; // Monday = 0
  return new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth(), l.getUTCDate() - dow)).toISOString().slice(0, 10);
}
const parseTz = (v) => Math.max(-840, Math.min(840, parseInt(v, 10) || 0));

// group: starter (once) | daily | weekly
const DEFS = [
  { id: "starter_first", group: "starter", title: "Grow your first tree", description: "Finish one focus session.", metric: "trees_total", target: 1, reward: 20 },
  { id: "starter_25", group: "starter", title: "Warm up", description: "Focus for 25 minutes in total.", metric: "minutes_total", target: 25, reward: 20 },
  { id: "starter_5", group: "starter", title: "Little grove", description: "Grow 5 trees.", metric: "trees_total", target: 5, reward: 30 },
  { id: "daily_30", group: "daily", title: "Morning ritual", description: "Focus for 30 minutes today.", metric: "minutes_today", target: 30, reward: 10 },
  { id: "daily_3", group: "daily", title: "Triple focus", description: "Grow 3 trees today.", metric: "trees_today", target: 3, reward: 15 },
  { id: "daily_goal", group: "daily", title: "Reach your goal", description: "Hit your daily focus goal.", metric: "minutes_today", target: "goal", reward: 20 },
  { id: "weekly_300", group: "weekly", title: "Steady week", description: "Focus for 300 minutes this week.", metric: "minutes_week", target: 300, reward: 60 },
  { id: "weekly_5days", group: "weekly", title: "Show up", description: "Focus on 5 different days this week.", metric: "days_week", target: 5, reward: 50 },
  { id: "weekly_10", group: "weekly", title: "Growing forest", description: "Grow 10 trees this week.", metric: "trees_week", target: 10, reward: 40 },
];

async function compute(user, tz) {
  const now = new Date();
  const today = dayKey(now, tz);
  const week = weekKey(now, tz);
  const sessions = await Session.find({ user: user._id, status: "completed" })
    .select("durationMinutes startedAt")
    .lean();

  const m = { trees_total: sessions.length, minutes_total: 0, minutes_today: 0, trees_today: 0, minutes_week: 0, trees_week: 0, days_week: 0 };
  const days = new Set();
  for (const s of sessions) {
    m.minutes_total += s.durationMinutes;
    const dk = dayKey(s.startedAt, tz);
    if (dk === today) {
      m.minutes_today += s.durationMinutes;
      m.trees_today += 1;
    }
    if (weekKey(s.startedAt, tz) === week) {
      m.minutes_week += s.durationMinutes;
      m.trees_week += 1;
      days.add(dk);
    }
  }
  m.days_week = days.size;

  const claimed = new Set(user.claimedChallenges || []);
  return DEFS.map((d) => {
    const period = d.group === "starter" ? "once" : d.group === "daily" ? today : week;
    const target = d.target === "goal" ? user.dailyGoal || 60 : d.target;
    const value = Math.min(m[d.metric], target);
    return {
      id: d.id,
      group: d.group,
      title: d.title,
      description: d.target === "goal" ? `Focus for ${target} minutes today (your daily goal).` : d.description,
      target,
      value,
      reward: d.reward,
      done: m[d.metric] >= target,
      claimed: claimed.has(`${d.id}:${period}`),
      claimKey: `${d.id}:${period}`,
    };
  });
}

router.get("/", async (req, res) => {
  try {
    const list = await compute(req.user, parseTz(req.query.tz));
    res.json({ challenges: list.map(({ claimKey, ...rest }) => rest) });
  } catch (error) {
    console.error("Challenges error:", error.message);
    res.status(500).json({ message: "Could not load challenges." });
  }
});

router.post("/claim", async (req, res) => {
  try {
    const id = typeof req.body.id === "string" ? req.body.id : "";
    const list = await compute(req.user, parseTz(req.body.tz));
    const c = list.find((x) => x.id === id);
    if (!c) return res.status(404).json({ message: "Unknown challenge." });
    if (!c.done) return res.status(400).json({ message: "Finish the challenge first." });
    if (c.claimed) return res.status(409).json({ message: "Reward already claimed." });

    req.user.claimedChallenges = [...(req.user.claimedChallenges || []), c.claimKey].slice(-300);
    req.user.coins += c.reward;
    await req.user.save();
    await notify(req.user, "milestone", "Reward claimed 🎁", `${c.title}: +${c.reward} coins.`);
    res.json({ message: `+${c.reward} coins — ${c.title}`, coins: req.user.coins });
  } catch (error) {
    console.error("Claim error:", error.message);
    res.status(500).json({ message: "Could not claim the reward." });
  }
});

module.exports = router;