# Single-table design. See docs/access-patterns.md for the patterns these keys serve.
resource "aws_dynamodb_table" "this" {
  #checkov:skip=CKV_AWS_119:AWS-owned encryption key (free) is used deliberately; a CMK costs ~$1/month with no practical benefit at this scale.
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  attribute {
    name = "GSI2PK"
    type = "S"
  }

  attribute {
    name = "GSI2SK"
    type = "S"
  }

  # Workout history by start time (patterns 5-6).
  global_secondary_index {
    name = "GSI1"
    key_schema {
      attribute_name = "GSI1PK"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "GSI1SK"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }

  # Sync feed: everything for a user ordered by updated_at (pattern 7).
  global_secondary_index {
    name = "GSI2"
    key_schema {
      attribute_name = "GSI2PK"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "GSI2SK"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}
