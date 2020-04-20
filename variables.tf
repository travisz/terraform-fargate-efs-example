variable "region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "az_count" {
  description = "Number of AZs in the given AWS region"
  default     = "2"
}

variable "app_port" {
  type = number
}

variable "ecs_cluster_name" {
  description = "Name for the ECS Cluster"
  type        = string
}

variable "app_image" {
  description = "Docker image to run in the container"
  default     = "nginx:latest"
}

variable "app_name" {
  description = "Main of the application/container to display in ECS"
}

variable "ecs_cpu" {
  default = 256
  type    = number
}

variable "ecs_mem" {
  default = 1024
  type    = number
}

variable "container_mount_path" {
  default = "/var/www/html"
  type    = string
}

variable "platform_version" {
  default = "LATEST"
  type    = string
}

variable "app_count" {
  description = "The number of ECS tasks to launch"
  type        = string
}
