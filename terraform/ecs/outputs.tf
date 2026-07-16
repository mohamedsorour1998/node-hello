output "region" {
  description = "AWS region."
  value       = var.region
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = module.ecs.cluster_arn
}

output "service_name" {
  description = "ECS service name."
  value       = local.name
}

output "image" {
  description = "Deployed container image."
  value       = var.image
}

# The Fargate task's public IP is assigned at runtime (not a Terraform-managed
# attribute), so surface a ready-to-run command to fetch it.
output "get_public_ip_command" {
  description = "Command to resolve the running task's public IP."
  value       = <<-EOT
    aws ecs list-tasks --cluster ${module.ecs.cluster_name} --service-name ${local.name} --region ${var.region} --query 'taskArns[0]' --output text \
    | xargs -I{} aws ecs describe-tasks --cluster ${module.ecs.cluster_name} --tasks {} --region ${var.region} \
        --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text \
    | xargs -I{} aws ec2 describe-network-interfaces --network-interface-ids {} --region ${var.region} \
        --query 'NetworkInterfaces[0].Association.PublicIp' --output text
  EOT
}
