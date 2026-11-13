variable "environment" {
  description = "Deployment environment name (local or prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "use_localstack" {
  description = "Route AWS API calls to LocalStack instead of live AWS"
  type        = bool
  default     = false
}

variable "desired_count" {
  description = "Number of ECS Fargate containers to run"
  type        = number
  default     = 2
}

variable "image_tag" {
  description = "Immutable container image tag to deploy"
  type        = string
  default     = "v1.0.0"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localstack:4566"
}
