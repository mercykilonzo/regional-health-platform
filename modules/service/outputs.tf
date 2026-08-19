output "alb_dns_name" {
  description = "ALB DNS name. Use this to reach the service — never the instance IP directly."
  value       = aws_lb.service.dns_name
}

output "instance_id" {
  description = "EC2 instance ID. Used in Gate 2 negative tests."
  value       = aws_instance.service.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance."
  value       = aws_instance.service.private_ip
}

output "security_group_id" {
  description = "Instance SG ID. Verify no 0.0.0.0/0 ingress exists."
  value       = aws_security_group.instance.id
}

output "alb_security_group_id" {
  description = "ALB SG ID."
  value       = aws_security_group.alb.id
}
