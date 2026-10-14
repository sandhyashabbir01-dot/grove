const jwt = require("jsonwebtoken");
const User = require("../models/User");

// Verifies the login token and puts the user on req.user
module.exports = async function authenticate(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ message: "Please log in first." });
    }
    if (!process.env.JWT_SECRET) {
      return res.status(500).json({ message: "Authentication is not configured." });
    }
    const token = authHeader.split(" ")[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await User.findById(decoded.userId);
    if (!user) {
      return res.status(401).json({ message: "User account not found." });
    }
    if (!user.unlockedTrees || user.unlockedTrees.length === 0) user.unlockedTrees = ["teal"];
    if (!user.selectedTree) user.selectedTree = "teal";
    req.user = user;
    next();
  } catch (error) {
    console.error("Authentication error:", error.message);
    return res.status(401).json({ message: "Invalid or expired login token." });
  }
};