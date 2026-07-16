output "container_name" {
  description = "Name of the running container."
  value       = docker_container.app.name
}

output "container_id" {
  description = "ID of the running container."
  value       = docker_container.app.id
}

output "image" {
  description = "Image reference that was deployed."
  value       = docker_image.app.name
}

output "app_url" {
  description = "URL for the application root endpoint."
  value       = "http://localhost:${var.host_port}/"
}

output "health_url" {
  description = "URL for the application health endpoint."
  value       = "http://localhost:${var.host_port}/health"
}
