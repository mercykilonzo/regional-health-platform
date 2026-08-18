# `modules/data` — publish external MySQL credentials to Secrets Manager

The database is **Aiven for MySQL** — a real managed MySQL living outside this
Terraform. RDS was dropped because it is not on LocalStack's free tier.

This module therefore does **not create a database**. It has one job: take
credentials that already exist and publish them into Secrets Manager using the
envelope the application resolves at boot.

That is still the graded piece. C3 is about the **runtime-injection path** — the
app fetching its credentials at boot and never seeing them in code, an image, or
user-data. Who provisions the engine is not what is being marked.

## Usage

```hcl
module "data" {
  source = "git::https://github.com/mercykilonzo/regional-health-platform.git//modules/data?ref=v0.1.0"

  db_host = var.db_host      # from TF_VAR_db_host
  db_port = var.db_port      # Aiven-assigned high port, NOT 3306
  db_name = var.db_name

  db_username = var.db_username   # avnadmin
  db_password = var.db_password    # from TF_VAR_db_password, sensitive

  tags = { Project = "regional-health", Owner = "mercy" }
}
```

Pin `?ref=` to a **tag or commit SHA**, never a branch — a teammate's next commit
would otherwise silently change what your root deploys.

## Where the credentials come from

```
Aiven service page
      │  host · port · user (avnadmin) · password
      ▼
GitHub Actions secrets  (and your local shell for manual applies)
      │  TF_VAR_db_host, TF_VAR_db_port, TF_VAR_db_username, TF_VAR_db_password
      ▼
this module
      │  jsonencode -> secret_string
      ▼
Secrets Manager  ──ARN only──▶  user-data  ──▶  app calls GetSecretValue at boot
```

**Never** a committed `.tfvars`. `*.tfvars` is gitignored specifically because it
is the likeliest place for someone to park these values.

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `db_host` | string | **required** | No default — a default credential is worse than a missing one |
| `db_port` | number | **required** | Aiven assigns a high port; assuming 3306 will fail |
| `db_username` | string | `avnadmin` | Aiven's default |
| `db_password` | string | **required**, `sensitive` | From Aiven, never generated here |
| `db_name` | string | `defaultdb` | Aiven's default database |
| `secret_name` | string | `regional-health/db` | |
| `kms_key_id` | string | `null` | AWS-managed key if unset |
| `tags` | map(string) | `{}` | |

Host, port and password have **no defaults on purpose**. A missing value fails
loudly at plan time; a defaulted one fails mysteriously at boot.

## Outputs

`db_endpoint` · `db_port` · `db_name` · `db_username` · `secret_arn` ·
`secret_name` · `secret_version_id`

**No `db_password` output**, by design. Exposing it would copy the value into the
caller's state, into `terraform output`, and into any CI step that echoes
outputs. Terraform would mark it sensitive and still write it to all three.

`db_endpoint` is named for the host to keep the interface stable for roots
written against the earlier RDS version.

## The credential envelope

```json
{
  "engine":   "mysql",
  "username": "avnadmin",
  "password": "<from Aiven>",
  "host":     "mysql-xxxx.a.aivencloud.com",
  "port":     12345,
  "dbname":   "defaultdb"
}
```

Keys are **exactly** those six. That is the contract `api/secrets.js` parses, and
it matches the shape AWS writes for RDS-managed secrets — so the application is
portable to a real AWS account with an RDS-managed secret and no code change.

**The Aiven CA certificate is deliberately not in this envelope.** Aiven requires
TLS, so the app needs the CA — but a CA certificate is a *public* certificate,
not a credential. It travels with the image or via user-data. Adding a seventh
key would break the contract the app and the grader both expect.

*(Practical note: committing `aiven-ca.pem` is safe from a gitleaks perspective —
its rules target `PRIVATE KEY` blocks, not `CERTIFICATE` blocks. Verify rather
than assume, and if it does flag, use a `.gitleaksignore` entry with a stated
reason rather than weakening the rule.)*

## Terraform state is a credential store

`var.db_password` is marked `sensitive`, which keeps it out of plan output and CLI
logs. **It does not keep it out of state** — the provider must store the value it
sent to the API. Identical discipline to the RDS version:

- no plaintext secret in git or in the image;
- the state backend is encrypted, versioned, non-public, gitignored;
- `trivy config` proves those bucket properties.

## What this module cannot verify

It writes credentials; it does not test them. A wrong password produces a
perfectly valid secret and a `/readyz` that returns 503 at boot — which is the
correct behaviour and exactly the C4 evidence, but worth knowing when debugging.

**Aiven's free tier sleeps when idle.** A cold service refuses connections until
it wakes, which looks identical to a bad credential. Hit the service once before
you start working, and check that before blaming this module.

## Free-tier limits (Aiven)

| Limit | Value | Relevance |
|---|---|---|
| Services | 1 MySQL per account | Use your **own personal** account; do not share |
| Storage | 1 GB | 10,000 patients is a few MB |
| Connections | 76 | Matters for the OPS-2202 replay: pool sizing must stay under this ceiling, which is a real constraint the local container never had |

That connection ceiling is worth carrying into the incident replay. In
Assignment 1 the pool was bounded only by what MySQL was configured to accept;
here there is a hard external limit, so a pool sized without regard to it will
fail with a connection error rather than queue.

## LocalStack fidelity notes

Carry these into `FIDELITY.md` **with your own detection method** — the brief
grades how you detected the divergence, not the list.

| Declared | What LocalStack appears to do |
|---|---|
| `kms_key_id` on the secret | Accepted; no CMK enforcement observed |
| `recovery_window_in_days = 0` | Behaviour around soft-delete differs from real AWS |

Note that the *database* is no longer emulated at all — Aiven is a real MySQL
server over TLS. Lock waits, InnoDB behaviour and connection limits are genuine,
which makes the OPS-2202 and OPS-2203 replays more faithful than they would have
been on emulated RDS.
