const express = require("express");
const jwt = require("jsonwebtoken");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || "super-secret-key";

app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.post("/login", (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: "Username and password are required" });
  }

  // Accept any dummy credentials
  const token = jwt.sign({ username }, JWT_SECRET, { expiresIn: "1h" });

  res.json({ token, username });
});

app.listen(PORT, () => {
  console.log(`Auth service running on port ${PORT}`);
});
