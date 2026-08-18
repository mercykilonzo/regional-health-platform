# =============================================================================
# modules/data — outputs
#
# The consumer needs enough to reach the database and to tell the application
# WHERE its credentials live. It never needs the password.
#
# There is deliberately no `db_password` output. Adding one would copy the value
# into the caller's state, into `terraform output`, and into any CI step that
# echoes outputs — the exact failure C3 grades. Terraform would mark it sensitive
# and still write it to those places.
#
# Host/port/username/dbname are echoed back rather than being pure pass-throughs
# so the root has a single source of truth and the seed script and the app agree
# on one set of values.
# =============================================================================

output "db_endpoint" {
  description = "MySQL hostname. Named db_endpoint to keep the interface stable for callers written against the previous RDS version."
  value       = var.db_host
}

output "db_port" {
  description = "MySQL port. Aiven-assigned, not 3306."
  value       = var.db_port
}

output "db_name" {
  description = "Database name. Consumed by the seed script."
  value       = var.db_name
}

output "db_username" {
  description = "MySQL username. Not a credential on its own; the password is, and it is not output."
  value       = var.db_username
}

output "secret_arn" {
  description = "ARN of the credential secret. This is what user-data receives and what the app resolves at boot — never the value."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Name of the credential secret."
  value       = aws_secretsmanager_secret.db.name
}

output "secret_version_id" {
  description = "Version currently holding the credentials. Cross-check against what /debug/secret-source reports the app resolved."
  value       = aws_secretsmanager_secret_version.db.version_id
}
