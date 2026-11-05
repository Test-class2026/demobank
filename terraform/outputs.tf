output "app_url" {
  description = "Open this in your browser"
  value       = "http://${aws_instance.demobank.public_ip}"
}

output "public_ip" {
  description = "The value for the EC2_HOST secret"
  value       = aws_instance.demobank.public_ip
}

output "ssh_command" {
  description = "Log in to the server"
  value       = "ssh -i ${trimsuffix(var.public_key_path, ".pub")} ubuntu@${aws_instance.demobank.public_ip}"
}
