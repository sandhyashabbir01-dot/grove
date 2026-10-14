// What the app is allowed to see about a user
module.exports = (u) => ({
  id: u._id,
  name: u.name,
  email: u.email,
  coins: u.coins,
  provider: u.provider || "email",
  notificationsEnabled: u.notificationsEnabled !== false,
  unlockedTrees: u.unlockedTrees && u.unlockedTrees.length ? u.unlockedTrees : ["teal"],
  selectedTree: u.selectedTree || "teal",
});