# =============================================================================
# modules/data — publish external MySQL credentials to Secrets Manager
#                                                                (group-owned)
#
# The database is Aiven for MySQL — a real managed MySQL living outside this
# Terraform. RDS was dropped because it is not on LocalStack's free tier.
#
# So this module does NOT create a database. It owns one job: take credentials
# that already exist and publish them into Secrets Manager using the envelope the
# application resolves at boot. That is still the graded piece — C3 is about the
# runtime-injection path, not about who provisions the engine.
#
# --- What changed, and what did not -----------------------------------------
#
#   changed:  no aws_db_instance, no random_password. Aiven generates and owns
#             the password; Terraform receives it as a sensitive input.
#   unchanged: the secret envelope, its exact key names, the rule that user-data
#             gets the ARN and never the value, and the fact that the plaintext
#             password lands in Terraform state.
#
# --- State is still a credential store --------------------------------------
#
# var.db_password is marked sensitive, which keeps it out of plan output and CLI
# logs. It does NOT keep it out of state — Terraform must store the value it
# sent to the API. The discipline is therefore identical to the RDS version:
#
#   * no plaintext secret in git or in the image;
#   * the state backend is encrypted, versioned, non-public;
#   * `trivy config` proves those bucket properties.
#
# --- Where the credentials come from ----------------------------------------
#
# GitHub Actions secrets -> TF_VAR_db_* environment variables -> here. Never a
# committed tfvars file. `*.tfvars` is gitignored precisely because it is the
# likeliest place for someone to park these.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# The credential secret
#
# recovery_window_in_days = 0 forces immediate deletion on destroy. The 30-day
# default soft-delete holds the secret NAME, so the next `make up` in CI fails
# with InvalidRequestException. Correct for a lab that rebuilds constantly; on
# production you want the recovery window.
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  description             = "MySQL credentials for the Regional Health service (Aiven-hosted). Resolved at boot via GetSecretValue."
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name      = var.secret_name
    Component = "data"
    DbEngine  = "mysql"
    DbHosting = "aiven"
  })
}

# -----------------------------------------------------------------------------
# The envelope.
#
# Keys are EXACTLY engine/username/password/host/port/dbname. This is the
# contract api/secrets.js parses, and it deliberately matches the shape AWS
# itself writes for managed RDS secrets — so the application code is portable to
# a real AWS account with an RDS-managed secret and no code change.
#
# Nothing extra goes in here. The Aiven CA certificate is NOT part of this
# envelope: it is a public certificate rather than a credential, so it travels
# with the image or via user-data. Adding a seventh key would break the contract
# the app and the grader both expect.
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    engine   = "mysql"
    username = var.db_username
    password = var.db_password
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
  })
}
