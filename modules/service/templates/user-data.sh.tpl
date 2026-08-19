#!/bin/bash
# =============================================================================
# user-data receives the SECRET ARN — never the credential value.
# The app calls GetSecretValue at boot and caches in memory.
#
# AWS_ENDPOINT_URL points the SDK at LocalStack. There is no if(isLocalStack)
# in the app — the same binary runs against real AWS with this variable unset.
#
# DB_HOST uses localhost.localstack.cloud instead of the RDS endpoint value
# because inside the instance container, localhost resolves to the instance
# itself, not the MySQL container. See FIDELITY.md item 7.
# =============================================================================
set -euo pipefail

cat >> /etc/environment << ENVEOF
SECRET_ARN=${secret_arn}
DB_HOST=localhost.localstack.cloud
DB_PORT=${db_port}
DB_NAME=${db_name}
APP_PORT=${app_port}
AWS_ENDPOINT_URL=http://localhost.localstack.cloud:4566
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
ENVEOF

set -a
source /etc/environment
set +a

systemctl enable nginx && systemctl start nginx || true

if systemctl list-unit-files | grep -q "^${service_name}.service"; then
  systemctl enable "${service_name}"
  systemctl start  "${service_name}"
fi
