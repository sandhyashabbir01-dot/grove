const express = require("express");
const trees = require("../config/trees");
const authenticate = require("../middleware/auth");
const notify = require("../utils/notify");

const router = express.Router();

const view = (u) => ({
  coins: u.coins,
  selected: u.selectedTree,
  trees: trees.map((t) => ({ ...t, owned: u.unlockedTrees.includes(t.id) })),
});

// List shop items
router.get("/", authenticate, (req, res) => res.json(view(req.user)));

// Buy a tree style with coins
router.post("/buy", authenticate, async (req, res) => {
  try {
    const tree = trees.find((t) => t.id === req.body.treeId);
    if (!tree) return res.status(400).json({ message: "Unknown tree." });
    if (req.user.unlockedTrees.includes(tree.id)) {
      return res.status(409).json({ message: "You already own this tree." });
    }
    if (req.user.coins < tree.cost) {
      return res.status(400).json({ message: "Not enough coins yet. Keep focusing!" });
    }
    req.user.coins -= tree.cost;
    req.user.unlockedTrees.push(tree.id);
    await req.user.save();
    await notify(req.user, "shop", "New tree unlocked 🛍️", `${tree.name} is yours. Select it in the Shop.`);
    return res.json(view(req.user));
  } catch (error) {
    console.error("Buy error:", error.message);
    return res.status(500).json({ message: "Could not buy this tree." });
  }
});

// Choose which owned tree to plant next
router.post("/select", authenticate, async (req, res) => {
  try {
    const { treeId } = req.body;
    if (!req.user.unlockedTrees.includes(treeId)) {
      return res.status(400).json({ message: "You do not own this tree." });
    }
    req.user.selectedTree = treeId;
    await req.user.save();
    return res.json(view(req.user));
  } catch (error) {
    console.error("Select error:", error.message);
    return res.status(500).json({ message: "Could not select this tree." });
  }
});

module.exports = router;