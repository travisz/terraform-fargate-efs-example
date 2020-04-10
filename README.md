# Fargate and EFS with Terraform

This code will create:
* VPC - Subnet(s), IGW, NAT Gateway(s)
* IAM - Role / Role Policy
* EC2 - Security Groups, Application Load Balancer and Listener
* EFS - File System and Mount Targets
* ECS - Cluster, Task Definition, Service
* Cloud Watch - Log Group

Make sure to review `variables.tf` and modify as needed.

The default container used is `nginx:latest`.

The EFS volume will mount to `/var/www/html` by default but will contain no data. The nginx container uses `/usr/share/nginx/html` by default.

**NOTE**: As of this writing `platform_version` for the Fargate reource needs to be set to `1.4.0` in your variable file or the CLI when running `terraform apply`. The AWS API is still returning `1.3.0` for `LATEST` but `1.4.0` is when support for EFS was introduced.

Example variable file:
```
region = "us-east-1"
vpc_cidr = "172.50.0.0/16"
vpc_name = "My-VPC"
environment = "development"
app_port = "80"
app_name = "nginx"
app_count = "1"
ecs_cluster_name = "appcluster"
container_mount_path = "/var/www/html"
platform_version = "1.4.0"
```
