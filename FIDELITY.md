# FIDELITY.md — Where LocalStack differed from real AWS

## 1. Security groups apply only at instance creation
LocalStack SG ingress rules apply only at the moment of instance launch.
Modifying a group after the instance starts opens no new ports on the
running instance. On real AWS, SG changes propagate within seconds.
Detection: added a rule post-launch, port remained blocked.
Real AWS verification: confirm rule propagation time with a live test.

## 2. Custom SGs do not filter traffic at runtime
Only the default security group is enforced at runtime on LocalStack.
Custom SGs are stored and returned by the API but traffic is not filtered.
Detection: port 22 was reachable despite no ingress rule permitting it.
Real AWS verification: confirm custom SG blocks traffic as declared.

## 3. IMDS has no IAM credentials endpoint
`http://169.254.169.254/latest/meta-data/iam/security-credentials/`
returns nothing on LocalStack. Instance-profile-based credentials cannot
be demonstrated. Static LocalStack credentials are used instead.
Real AWS verification: replace with an instance profile, verify
GetSecretValue succeeds without hardcoded keys.

## 4. RDS storage encryption is accepted but not applied
`storage_encrypted = true` is stored and returned by the API but no
actual KMS encryption is applied to the MySQL container.
Real AWS verification: verify KMS key usage in CloudTrail.

## 5. Docker socket is shared inside EC2 instances
The Docker socket is mounted inside each LocalStack EC2 instance. A
`docker run` inside creates a sibling container on the host, not a child.
On real EC2 this requires Docker to be installed and configured separately.

## 6. ELBv2 health checking is undocumented
The ALB target group health check is written as IaC and graded by trivy,
but LocalStack does not reliably implement active health checking or
unhealthy target removal. nginx carries real health routing in this lab.
Real AWS verification: verify ALB stops routing when /readyz returns 503.

## 7. RDS endpoint is localhost, not a hostname
LocalStack returns `localhost:<port>` as the RDS endpoint. Inside the EC2
instance container, localhost resolves to the instance itself, not the
MySQL container. Must use `localhost.localstack.cloud` which resolves to
the Docker bridge IP.
Real AWS verification: confirm endpoint DNS resolution inside the VPC.
