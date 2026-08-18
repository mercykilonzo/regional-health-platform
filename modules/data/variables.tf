# =============================================================================
# modules/data — inputs
#
# Defaults match the sizes the assignment specifies, so a caller that passes
# nothing still gets a correctly right-sized instance. Every default is
# justified in README.md rather than left as a magic number.
# =============================================================================

variable "identifier" {
  description = "RDS instance identifier. Distinct per caller so two roots can share the platform."
  type        = string
  default     = "regional-health-mysql"
}

variable "db_name" {
  description = "Name of the initial database created on the instance."
  type        = string
  default     = "capacity_lab"
}

variable "db_username" {
  description = "Master username for the MySQL instance. The password is generated, never supplied."
  type        = string
  default     = "app"

  validation {
    # RDS reserves 'admin' and MySQL reserves a few others; catching it here
    # fails at plan time instead of after a two-minute create.
    condition     = !contains(["admin", "root", "mysql", "guest"], lower(var.db_username))
    error_message = "db_username must not be a MySQL/RDS reserved name (admin, root, mysql, guest)."
  }
}

variable "instance_class" {
  description = "RDS instance class. db.t3.micro (2 vCPU / 1 GiB) is ample for a 10k-row dataset."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Storage in GiB. 20 is the RDS-MySQL minimum; the dataset is a few MB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "RDS MySQL requires at least 20 GiB of allocated storage."
  }
}

variable "engine_version" {
  description = "MySQL engine version. 8.0 matches Assignment 1, so InnoDB lock behaviour is comparable."
  type        = string
  default     = "8.0"
}

variable "secret_name" {
  description = "Secrets Manager secret name holding the DB credential envelope."
  type        = string
  default     = "regional-health/db"
}

variable "multi_az" {
  description = <<-EOT
    Multi-AZ deployment. Defaults to false for the lab: it halves cost and
    LocalStack does not emulate AZ failover anyway. The trade-off being
    accepted is that a single AZ loss takes the database down entirely, with
    recovery bounded by restore-from-backup rather than by failover.
  EOT
  type        = bool
  default     = false
}

variable "storage_encrypted" {
  description = <<-EOT
    Encryption at rest. Defaults true because `trivy config` requires it and it
    is correct on real AWS. NOTE: LocalStack returns this attribute as
    configured but applies no encryption — recorded in FIDELITY.md.
  EOT
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = <<-EOT
    Days of automated backups. 7 satisfies `trivy config` and is a defensible
    production floor. LocalStack does not actually take backups.
  EOT
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = <<-EOT
    Deliberately false. The graded evidence requires `terraform destroy` to
    succeed (evidence/01-iac/destroy.log) and CI recreates the stack from zero
    on every run. On a real production database this MUST be true — the
    divergence is stated here rather than hidden.
  EOT
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "Optional CMK ARN for RDS storage and the secret. Null uses the AWS-managed key."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
