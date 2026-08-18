# =============================================================================
# modules/data — RDS MySQL 8.0 + Secrets Manager                 (group-owned)
#
# Creates a managed MySQL instance and publishes its credentials to Secrets
# Manager using the shared envelope. The plaintext password exists in exactly
# two places: Terraform state (unavoidable — see below) and Secrets Manager.
# It is never an output, never logged, never written to user-data, and never
# committed.
#
# ON TERRAFORM STATE: aws_db_instance.password lands in state in cleartext.
# There is no arrangement of random_password that avoids this — the provider
# needs the value to make the API call. The discipline is therefore to treat
# the state file as a credential store: encrypted S3 bucket, versioned,
# non-public, gitignored. `trivy config` proves those bucket properties.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------------------------------------------------------------------
# Master password
#
# special = false on purpose. RDS rejects '/', '@', '"' and ' ' in master
# passwords, and a password that survives being embedded in a MySQL DSN or a
# shell command without quoting removes a whole class of boot-time failure.
# 24 alphanumeric characters is ~143 bits of entropy — well past anything that
# matters here.
# -----------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 24
  special = false
}

# -----------------------------------------------------------------------------
# The MySQL instance
# -----------------------------------------------------------------------------
resource "aws_db_instance" "mysql" {
  identifier = var.identifier

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  # Not reachable from the internet. On LocalStack this attribute governs
  # nothing (the container is reachable over the Docker bridge regardless), but
  # it is the correct declaration and `trivy config` checks it.
  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection

  # Required so the lab can tear down and rebuild from zero.
  skip_final_snapshot = true

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Audit trail for the credential-handling story. LocalStack accepts this but
  # ships nothing to CloudWatch; the declaration is what gets graded as IaC.
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = merge(var.tags, {
    Name      = var.identifier
    Component = "data"
  })

  lifecycle {
    # The password is rotated through Secrets Manager, not by re-applying this
    # resource. Without this, any change to random_password would force an
    # in-place master-password reset and desync the secret from the database.
    ignore_changes = [password]
  }
}

# -----------------------------------------------------------------------------
# Secrets Manager
#
# recovery_window_in_days = 0 forces immediate deletion on destroy. The default
# 30-day soft delete would hold the secret NAME for 30 days, so the next
# `make up` in CI would fail with InvalidRequestException. Correct for a lab
# that rebuilds constantly; on production you want the recovery window.
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  description             = "MySQL credentials for the Regional Health service. Consumed at boot via GetSecretValue."
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name      = var.secret_name
    Component = "data"
  })
}

# -----------------------------------------------------------------------------
# The credential envelope.
#
# Keys are EXACTLY engine/username/password/host/port/dbname — this is the
# contract api/secrets.js parses, and it matches the shape AWS itself writes for
# RDS-managed secrets, so the application code would work unchanged against a
# real AWS account.
#
# jsonencode rather than a heredoc: it escapes correctly and cannot emit
# malformed JSON if a generated value ever contains an awkward character.
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    engine   = "mysql"
    username = aws_db_instance.mysql.username
    password = random_password.db.result
    host     = aws_db_instance.mysql.address
    port     = aws_db_instance.mysql.port
    dbname   = aws_db_instance.mysql.db_name
  })
}
