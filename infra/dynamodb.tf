##############################################################################
# dynamodb.tf — DynamoDB table for storing votes
##############################################################################

# The Votes table stores one item per vote.
# PAY_PER_REQUEST billing means zero cost when idle, scaling automatically
# under load — ideal for dev/staging and unpredictable traffic patterns.

resource "aws_dynamodb_table" "votes" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"

  # Partition key — each candidate gets a unique ID
  hash_key = "candidateId"

  attribute {
    name = "candidateId"
    type = "S"
  }

  # Enable point-in-time recovery for production safety
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-votes-table"
  }
}
