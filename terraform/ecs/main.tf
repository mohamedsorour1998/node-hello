# Use the account's default VPC and its public subnets (Map public IP on launch).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  name = "node-hello"
  # Only the boolean "is a key provided?" is unwrapped — never the key value —
  # so it can be used in count/for_each without tainting them as sensitive.
  nr_enabled = nonsensitive(var.newrelic_license_key != "")
}

# Store the New Relic key as an encrypted SSM SecureString and inject it into
# the container via ECS `secrets`. This keeps the secret out of the task
# definition/plan and out of Terraform's for_each (which rejects sensitive
# values used directly in the services map).
resource "aws_ssm_parameter" "newrelic_license_key" {
  count = local.nr_enabled ? 1 : 0

  name  = "/${local.name}/NEW_RELIC_LICENSE_KEY"
  type  = "SecureString"
  value = var.newrelic_license_key
  tags  = var.tags
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.0"

  cluster_name = var.cluster_name

  services = {
    (local.name) = {
      cpu           = var.task_cpu
      memory        = var.task_memory
      desired_count = var.desired_count
      launch_type   = "FARGATE"

      # Place the task in a public subnet with a public IP so it can pull the
      # public GHCR image and be reachable for this demo (no ALB).
      assign_public_ip = true
      subnet_ids       = data.aws_subnets.default.ids
      vpc_id           = data.aws_vpc.default.id

      # Block apply until the service reaches steady state (task running).
      wait_for_steady_state = true

      # Single-task demo — no autoscaling needed.
      enable_autoscaling = false

      # Let the task execution role read the New Relic SSM SecureString.
      task_exec_ssm_param_arns = local.nr_enabled ? [aws_ssm_parameter.newrelic_license_key[0].arn] : []

      container_definitions = {
        (local.name) = {
          essential              = true
          image                  = var.image
          readonlyRootFilesystem = false

          portMappings = [
            {
              name          = "http"
              containerPort = var.container_port
              protocol      = "tcp"
            }
          ]

          environment = [
            { name = "PORT", value = tostring(var.container_port) },
            { name = "NEW_RELIC_APP_NAME", value = var.newrelic_app_name },
          ]

          # New Relic key injected from SSM (only when provided).
          secrets = local.nr_enabled ? [
            {
              name      = "NEW_RELIC_LICENSE_KEY"
              valueFrom = aws_ssm_parameter.newrelic_license_key[0].arn
            }
          ] : []

          # The module creates a CloudWatch log group and wires up the awslogs
          # driver automatically.
          enable_cloudwatch_logging = true
        }
      }

      # Security group for the task. NOTE: this opens the app port to the whole
      # internet for demo purposes — the app is a public, unauthenticated
      # hello-world. Lock this down (or front with an ALB/WAF) for real use.
      security_group_ingress_rules = {
        app = {
          description = "App HTTP port"
          from_port   = var.container_port
          to_port     = var.container_port
          ip_protocol = "tcp"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
      security_group_egress_rules = {
        all = {
          description = "Allow all outbound"
          ip_protocol = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
    }
  }

  tags = var.tags
}
