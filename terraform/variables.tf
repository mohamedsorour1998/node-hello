variable "docker_host" {
  description = <<-EOT
    Docker-compatible API endpoint. For rootless Podman this is the user socket
    (run `id -u` and replace 1000 if different). The provider also honours the
    DOCKER_HOST environment variable.
  EOT
  type        = string
  default     = "unix:///run/user/1000/podman/podman.sock"
}

variable "image" {
  description = "Container image reference to deploy."
  type        = string
  default     = "ghcr.io/mohamedsorour1998/node-hello:latest"
}

variable "build_local" {
  description = <<-EOT
    When true, build the image from the repository's Dockerfile instead of
    pulling it from the registry. Useful for a fully local flow that does not
    depend on GHCR visibility.
  EOT
  type        = bool
  default     = false
}

variable "container_name" {
  description = "Name of the created container."
  type        = string
  default     = "node-hello"
}

variable "internal_port" {
  description = "Port the app listens on inside the container."
  type        = number
  default     = 3000
}

variable "host_port" {
  description = "Host port mapped to the container port."
  type        = number
  default     = 8080
}

variable "log_level" {
  description = "Application log level (debug|info|warn|error)."
  type        = string
  default     = "info"
}

variable "restart_policy" {
  description = "Container restart policy."
  type        = string
  default     = "unless-stopped"
}

variable "newrelic_app_name" {
  description = "New Relic application name."
  type        = string
  default     = "node-hello"
}

variable "newrelic_license_key" {
  description = <<-EOT
    New Relic license/ingest key. Leave empty to run without New Relic.
    Provide via TF_VAR_newrelic_license_key or a gitignored terraform.tfvars.
    NEVER commit a real key.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}
