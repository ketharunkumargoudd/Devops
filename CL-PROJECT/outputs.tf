output "public_ip" {
  value = aws_instance.k8s.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.k8s.public_ip}"
}

output "shop_url" {
  value = "http://${aws_instance.k8s.public_ip}:30080"
}

output "grafana_url" {
  value = "http://${aws_instance.k8s.public_ip}:32000"
}

output "prometheus_url" {
  value = "http://${aws_instance.k8s.public_ip}:30090"
}
