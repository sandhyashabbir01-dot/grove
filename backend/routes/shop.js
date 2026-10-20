const express = require("express");
const trees = require("../config/trees");
const authenticate = require("../middleware/auth");
const notify = require("../utils/notify");

const router = express.Router();

const REAL_TREE_COST = 500; // keep in sync with kRealTreeCost in features.dart

const view = (u) => ({
  coins: u.coins,
  realTrees: u.realTrees || 0,
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

// Spend coins to request one real tree
router.post("/plant-real", authenticate, async (req, res) => {
  try {
    if (req.user.coins < REAL_TREE_COST) {
      return res.status(400).json({ message: `You need ${REAL_TREE_COST} coins to request a real tree.` });
    }
    req.user.coins -= REAL_TREE_COST;
    req.user.realTrees = (req.user.realTrees || 0) + 1;
    await req.user.save();
    await notify(req.user, "shop", "Real tree requested 🌍", "Thank you! Your real tree request has been saved.");
    return res.json(view(req.user));
  } catch (error) {
    console.error("Real tree error:", error.message);
    return res.status(500).json({ message: "Could not save your real tree request." });
  }
});

module.exports = router;