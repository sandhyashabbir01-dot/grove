const DEFAULT_TAGS = ["Study", "Work", "Sport", "Rest", "Social", "Entertainment", "Other"];

module.exports = function publicUser(user) {
  const whitelist = user.whitelistApps || [];
  return {
    id: String(user._id),
    name: user.name,
    email: user.email,
    coins: user.coins,
    provider: user.provider || "email",
    unlockedTrees: user.unlockedTrees && user.unlockedTrees.length ? user.unlockedTrees : ["teal"],
    selectedTree: user.selectedTree || "teal",
    notificationsEnabled: user.notificationsEnabled !== false,
    tags: user.tags && user.tags.length ? user.tags : DEFAULT_TAGS,
    whitelist, // the app reads this one
    whitelistApps: whitelist, // kept for older versions of the app
    graceSeconds: user.graceSeconds || 0,
    dailyGoal: user.dailyGoal || 60,
    friends: (user.friends || []).map(String),
    achievementsSeen: user.achievementsSeen || [],
    realTrees: user.realTrees || 0,
    subscriptionStatus: user.subscriptionStatus || "free",
    subscriptionPlan: user.subscriptionPlan || "none",
    subscriptionPeriodEnd: user.subscriptionPeriodEnd || null,
  };
};