variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "image" {
  description = "Container image to run on ECS (public GHCR image published by CI)."
  type        = string
  default     = "ghcr.io/mohamedsorour1998/node-hello:latest"
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
  default     = "node-hello"
}

variable "container_port" {
  description = "Port the app listens on inside the container."
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "newrelic_app_name" {
  description = "New Relic application name."
  type        = string
  default     = "node-hello"
}

variable "newrelic_license_key" {
  description = <<-EOT
    New Relic license key. Leave empty to run without New Relic. Provide via a
    gitignored terraform.tfvars or TF_VAR_newrelic_license_key. NEVER commit it.
    (For production, prefer AWS Secrets Manager / SSM + container `secrets`.)
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    Project   = "node-hello"
    ManagedBy = "terraform"
    Component = "ecs-fargate"
  }
}
