const express = require("express");
const jwt = require("jsonwebtoken");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, ScanCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || "super-secret-key";
const TABLE_NAME = process.env.DYNAMODB_TABLE || "Votes";
const AWS_REGION = process.env.AWS_REGION || "eu-west-2";

// DynamoDB client — uses IAM role credentials from the EKS node automatically
const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

// JWT verification middleware
function verifyToken(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Missing or invalid token" });
  }

  try {
    const decoded = jwt.verify(header.split(" ")[1], JWT_SECRET);
    req.user = decoded;
    next();
  } catch {
    return res.status(401).json({ error: "Invalid token" });
  }
}

app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// GET /votes — scan the Votes table and return all candidates with their counts
app.get("/votes", verifyToken, async (req, res) => {
  try {
    const result = await docClient.send(new ScanCommand({ TableName: TABLE_NAME }));
    const votes = (result.Items || [])
      .map((item) => ({ candidate: item.candidateId, count: item.voteCount || 0 }))
      .sort((a, b) => b.count - a.count);
    res.json(votes);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /vote — atomically increment the vote count for a candidate
app.post("/vote", verifyToken, async (req, res) => {
  const { candidate } = req.body;
  if (!candidate) {
    return res.status(400).json({ error: "Candidate is required" });
  }

  try {
    await docClient.send(new UpdateCommand({
      TableName: TABLE_NAME,
      Key: { candidateId: candidate },
      UpdateExpression: "ADD voteCount :inc",
      ExpressionAttributeValues: { ":inc": 1 },
    }));
    res.json({ message: "Vote recorded", candidate });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Backend API running on port ${PORT}`);
});
