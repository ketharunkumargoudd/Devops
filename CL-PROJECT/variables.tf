variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "shop-k8s"
}

variable "instance_type" {
  description = "EC2 size. t3.large (2 vCPU / 8 GB) is the minimum comfortable size for k3s + Prometheus + Grafana"
  type        = string
  default     = "t3.large"
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (find it with: curl ifconfig.me)"
  type        = string
}
