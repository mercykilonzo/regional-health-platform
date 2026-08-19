variable "service_name" {
  description = "Base name for resources in this module."
  type        = string
  default     = "regional-health"
}

variable "app_ami_id" {
  description = "AMI ID produced by the CI image-build step."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{12}$", var.app_ami_id))
    error_message = "app_ami_id must be ami- followed by exactly 12 lowercase hexadecimal characters."
  }
}

variable "instance_type" {
  description = "EC2 instance type used for the service."
  type        = string
  default     = "t3.small"
}

variable "app_port" {
  description = "Port on which the application listens."
  type        = number
  default     = 3000

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "app_port must be a valid TCP port between 1 and 65535."
  }
}

variable "secret_arn" {
  description = "ARN of the database credential secret. The secret value must never be passed here."
  type        = string
}

variable "db_endpoint" {
  description = "Aiven MySQL hostname."
  type        = string

  validation {
    condition     = length(trimspace(var.db_endpoint)) > 0
    error_message = "db_endpoint must be set to the Aiven MySQL hostname."
  }
}

variable "db_port" {
  description = "Aiven-assigned MySQL TCP port."
  type        = number

  validation {
    condition     = var.db_port > 0 && var.db_port <= 65535
    error_message = "db_port must be a valid TCP port between 1 and 65535."
  }
}

variable "db_name" {
  description = "MySQL database name."
  type        = string
  default     = "defaultdb"
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
