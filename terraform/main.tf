provider "docker" {
  host = var.docker_host
}

# The application image: either pulled from the registry (default) or built
# locally from the repository Dockerfile when build_local = true.
resource "docker_image" "app" {
  name         = var.image
  keep_locally = true

  dynamic "build" {
    for_each = var.build_local ? [1] : []
    content {
      context = abspath("${path.module}/..")
      tag     = [var.image]
    }
  }
}

resource "docker_container" "app" {
  name     = var.container_name
  image    = docker_image.app.image_id
  hostname = var.container_name

  ports {
    internal = var.internal_port
    external = var.host_port
  }

  # Runtime configuration. The New Relic key is only injected when provided so
  # the agent stays disabled by default (see index.js).
  env = concat(
    [
      "PORT=${var.internal_port}",
      "LOG_LEVEL=${var.log_level}",
      "NEW_RELIC_APP_NAME=${var.newrelic_app_name}",
    ],
    var.newrelic_license_key != "" ? ["NEW_RELIC_LICENSE_KEY=${var.newrelic_license_key}"] : [],
  )

  healthcheck {
    test         = ["CMD", "node", "-e", "require('http').get('http://127.0.0.1:${var.internal_port}/health',res=>process.exit(res.statusCode===200?0:1)).on('error',()=>process.exit(1))"]
    interval     = "30s"
    timeout      = "3s"
    retries      = 3
    start_period = "5s"
  }

  restart = var.restart_policy

  # Replace the container whenever the underlying image changes.
  lifecycle {
    replace_triggered_by = [docker_image.app.image_id]
  }
}
