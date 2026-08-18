# =============================================================================
# modules/data — inputs
#
# The connection details come from the Aiven service page and are supplied as
# TF_VAR_db_* environment variables sourced from GitHub Actions secrets. There
# are deliberately no defaults for host/username/password: a default credential
# is worse than a missing one, because a missing one fails loudly at plan time.
# =============================================================================

variable "db_host" {
  description = "Aiven MySQL hostname, e.g. mysql-xxxx-yyyy.a.aivencloud.com. From the service page, never committed."
  type        = string

  validation {
    condition     = length(trimspace(var.db_host)) > 0
    error_message = "db_host must be set. Supply it as TF_VAR_db_host from a GitHub Actions secret or your local environment."
  }
}

variable "db_port" {
  description = <<-EOT
    Aiven MySQL port. NOT 3306 — Aiven assigns a high port per service, so this
    has no default on purpose. Copy it from the service page.
  EOT
  type        = number

  validation {
    condition     = var.db_port > 0 && var.db_port <= 65535
    error_message = "db_port must be a valid TCP port (1-65535). Aiven assigns a high port per service; check the service page rather than assuming 3306."
  }
}

variable "db_username" {
  description = "MySQL username. Aiven's default is avnadmin."
  type        = string
  default     = "avnadmin"
}

variable "db_password" {
  description = <<-EOT
    MySQL password, generated and owned by Aiven.

    Marked sensitive, which keeps it out of plan output and CLI logs. It does NOT
    keep it out of Terraform state — the provider must store the value it sent to
    the API. Treat the state backend as a credential store: encrypted, versioned,
    non-public.

    Supply as TF_VAR_db_password. Never in a committed tfvars file.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) > 0
    error_message = "db_password must be set. Supply it as TF_VAR_db_password from a GitHub Actions secret or your local environment."
  }
}

variable "db_name" {
  description = "Database name. Aiven's default is defaultdb; the lab schema can live there or in a database you create."
  type        = string
  default     = "defaultdb"
}

variable "secret_name" {
  description = "Secrets Manager secret name holding the credential envelope."
  type        = string
  default     = "regional-health/db"
}

variable "kms_key_id" {
  description = "Optional CMK ARN for the secret. Null uses the AWS-managed key. LocalStack accepts this but enforces nothing — a FIDELITY.md candidate."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the secret."
  type        = map(string)
  default     = {}
}
