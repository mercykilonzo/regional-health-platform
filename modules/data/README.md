# `modules/data` — RDS MySQL 8.0 + Secrets Manager

Creates a managed MySQL instance and publishes its credentials to Secrets
Manager using the envelope the application expects.

## Usage

```hcl
module "data" {
  source = "git::https://github.com/mercykilonzo/regional-health-platform.git//modules/data?ref=v0.1.0"

  identifier  = "regional-health-mysql"
  db_name     = "capacity_lab"
  db_username = "app"
  tags        = { Project = "regional-health", Owner = "mercy" }
}
```

Pin `?ref=` to a **tag or commit SHA**, never a branch. Same supply-chain
discipline C5 grades on actions and base images, applied to our own modules —
and it stops a mid-flight commit on `main` silently changing someone's deploy.

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `identifier` | string | `regional-health-mysql` | Distinct per caller |
| `db_name` | string | `capacity_lab` | Initial database |
| `db_username` | string | `app` | Validated against RDS reserved names |
| `instance_class` | string | `db.t3.micro` | 2 vCPU / 1 GiB |
| `allocated_storage` | number | `20` | GiB; validated `>= 20` |
| `engine_version` | string | `8.0` | |
| `secret_name` | string | `regional-health/db` | |
| `multi_az` | bool | `false` | See trade-off below |
| `storage_encrypted` | bool | `true` | LocalStack echoes, does not apply |
| `backup_retention_period` | number | `7` | Satisfies `trivy config` |
| `deletion_protection` | bool | `false` | Lab requires destroy; see below |
| `kms_key_id` | string | `null` | AWS-managed key if unset |
| `tags` | map(string) | `{}` | |

## Outputs

`db_endpoint` · `db_port` · `db_name` · `db_username` · `secret_arn` ·
`secret_name` · `secret_version_id`

**There is no `db_password` output, by design.** Exposing it would copy the
value into the caller's state, into `terraform output`, and into any CI log that
prints outputs. Consumers receive the **ARN** and resolve the value themselves
at runtime via `GetSecretValue`.

## Right-sizing rationale

| Choice | Value | Why |
|---|---|---|
| Instance class | `db.t3.micro` | 10,000 patients is a few MB. The dataset fits entirely in the buffer pool, so the smallest general-purpose class is not a compromise — it is correct. |
| Storage | 20 GiB `gp3` | RDS-MySQL minimum. The data is a rounding error against it; provisioning more would be waste, not headroom. |
| Engine | MySQL `8.0` | Matches Assignment 1, so InnoDB lock behaviour, `innodb_lock_wait_timeout` and connection limits reproduce faithfully — which is what makes the OPS-2202 and OPS-2203 replays meaningful rather than decorative. |
| Multi-AZ | `false` | **Trade-off accepted:** losing the AZ loses the database. Recovery is bounded by restore-from-backup (minutes-to-hours) rather than failover (~60–120 s). Defensible for a lab; a real admissions system would not accept it. |
| Backup retention | 7 days | Satisfies `trivy config` and is a defensible production floor. LocalStack takes no backups. |
| Deletion protection | `false` | Graded evidence needs `terraform destroy` to succeed, and CI rebuilds from zero every run. **On production this must be `true`.** |

## The credential envelope

`aws_secretsmanager_secret_version` writes exactly:

```json
{
  "engine":   "mysql",
  "username": "app",
  "password": "<generated>",
  "host":     "<rds address>",
  "port":     3306,
  "dbname":   "capacity_lab"
}
```

Those key names are the contract `api/secrets.js` parses. They deliberately
match the shape AWS writes for RDS-managed secrets, so the application code
would work unchanged against a real AWS account with `AWS_ENDPOINT_URL` unset.

## Terraform state is a credential store

`aws_db_instance.password` lands in state **in cleartext**. No arrangement of
`random_password` avoids this — the provider needs the value to make the API
call. The rule is therefore:

- no plaintext secret in git or in the image;
- the state backend is treated as a credential store: **encrypted, versioned,
  non-public, gitignored**;
- `trivy config` proves those bucket properties.

## LocalStack fidelity notes

Carry these into `FIDELITY.md` **with your own detection method** — the brief
grades how you detected the divergence, not the list itself.

| Declared | What LocalStack appears to do |
|---|---|
| `storage_encrypted = true` | Returned as configured; no encryption applied |
| `backup_retention_period = 7` | No automated backups taken |
| `enabled_cloudwatch_logs_exports` | Accepted; nothing shipped to CloudWatch |
| `publicly_accessible = false` | Governs nothing — reachable over the Docker bridge either way |
| `kms_key_id` | Accepted; no CMK enforcement |

Also note: the endpoint RDS returns is on `localhost:<port>`. From **inside**
the EC2 instance container, `localhost` is the instance itself — use the bridge
address or `localhost.localstack.cloud`. This is the first of the assignment's
"four things that will break first".

## Lifecycle notes

- **`ignore_changes = [password]`** on the instance: rotation happens through
  Secrets Manager, not by re-applying this resource. Without it, any change to
  `random_password` forces an in-place master-password reset and desyncs the
  secret from the database.
- **`recovery_window_in_days = 0`** on the secret: the 30-day default
  soft-delete holds the secret *name* for 30 days, so the next `make up` fails
  with `InvalidRequestException`. Correct for a lab that rebuilds constantly; on
  production you want the recovery window.
