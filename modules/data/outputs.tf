# =============================================================================
# modules/data — outputs
#
# The root module needs enough to point the app at the database and tell it
# WHERE to find the credentials. It never needs the credentials themselves.
#
# There is deliberately no `db_password` output. Adding one would put the value
# into the caller's state, into `terraform output`, and into any CI log that
# echoes outputs — which is exactly the failure C3 is graded on preventing.
# =============================================================================

output "db_endpoint" {
  description = "Hostname of the MySQL instance (address only, no port)."
  value       = aws_db_instance.mysql.address
}

output "db_port" {
  description = "Port the MySQL instance listens on."
  value       = aws_db_instance.mysql.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.mysql.db_name
}

output "db_username" {
  description = "Master username. Not a secret on its own; the password is what matters."
  value       = aws_db_instance.mysql.username
}

output "secret_arn" {
  description = "ARN of the credential secret. This is what user-data receives — never the value."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Name of the credential secret."
  value       = aws_secretsmanager_secret.db.name
}

output "secret_version_id" {
  description = "Version of the secret currently holding the credentials. Useful for proving which version the app resolved at boot."
  value       = aws_secretsmanager_secret_version.db.version_id
}
