provider "aws" {
  region = var.region
}

# Grab the Region
data "aws_region" "current" {}

### IAM
resource "aws_iam_role" "ecs" {
  name               = "${var.app_name}-ecs-iam-role"
  assume_role_policy = file("${path.module}/policies/ecs-task-execution-role.json")
}

resource "aws_iam_role_policy" "ecs" {
  name = "${var.app_name}-ecs-iam-policy"
  role = aws_iam_role.ecs.name

  policy = file ("${path.module}/policies/ecs-task-execution-role-policy.json")
}

### Networking

# Grab the currently available AZs for the region
data "aws_availability_zones" "available" {}

# Create the VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name        = var.vpc_name
    Environment = var.environment
  }
}

# Private Subnets based on az_count variable
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# Publc Subnets based on az_count variable
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# IGW for the public subnet
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.vpc_name}-{var.environment}-IGW"
    Environment = var.environment
  }
}

# Route table entry for public subnet traffic to the IGW
resource "aws_route" "public" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# EIP for NAT Gateway
resource "aws_eip" "nat-gw" {
  count      = var.az_count
  vpc        = true
  depends_on = ["aws_internet_gateway.gw"]
}

# NAT Gateway, one per AZ for the private subnet to have internet access
resource "aws_nat_gateway" "nat-gw" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.nat-gw.*.id, count.index)
}

# Route table for the private subnets
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.nat-gw.*.id, count.index)
  }
}

# Associate the route tables to the private subnets
resource "aws_route_table_association" "private" {
  count          =  var.az_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

### Security Groups

# Application Load Balancer Security Group
# Modify this to allow ports for your application or to restrict access
resource "aws_security_group" "alb" {
  name        = "terraform-ecs-alb"
  description = "Controls Access to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Restrict traffic to the ECS Cluster, only allow it to come from the ALB
resource "aws_security_group" "ecs" {
  name        = "terraform-ecs-task"
  description = "Allow access from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EFS Security Group
resource "aws_security_group" "efs-sg" {
  name        = "terraform-efs"
  description = "Allow EFS Traffic from the Private Subnet"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = "2049"
    to_port     = "2049"
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private.*.cidr_block
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Application Load Balancer

resource "aws_alb" "main" {
  name            = "terraform-ecs-test"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.alb.id]
}

resource "aws_alb_target_group" "app" {
  name        = "terraform-ecs-test"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_alb_listener" "app_front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}

### EFS
resource "aws_efs_file_system" "efs" {
  creation_token = "terraform-efs-fs"
  encrypted = true
}

resource "aws_efs_mount_target" "efs" {
  file_system_id  = "${aws_efs_file_system.efs.id}"
  count           = var.az_count
  subnet_id       = element(aws_subnet.private.*.id, count.index)
  security_groups = ["${aws_security_group.efs-sg.id}"]
}

### ECS

# Create the ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name
}

# Template for the Task Definition
data "template_file" "task_definition" {
  template = "${file("${path.module}/task-definition.json")}"

  vars = {
    image_url            = var.app_image
    container_name       = var.app_name
    ecs_cpu              = var.ecs_cpu
    ecs_mem              = var.ecs_mem
    app_port             = var.app_port
    container_mount_path = var.container_mount_path
    source_volume        = "efs-volume"
    log_group_region     = data.aws_region.current.name
    log_group_name       = "${aws_cloudwatch_log_group.app.name}"
    log_stream_prefix    = var.app_name
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = "${data.template_file.task_definition.rendered}"
  execution_role_arn       = aws_iam_role.ecs.arn
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_mem

  volume {
    name = "efs-volume"

    efs_volume_configuration {
      file_system_id = aws_efs_file_system.efs.id
      root_directory = "/"
    }
  }
}

resource "aws_ecs_service" "main" {
  name             = var.app_name
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = var.app_count
  launch_type      = "FARGATE"
  platform_version = var.platform_version

  network_configuration {
    security_groups = [aws_security_group.ecs.id]
    subnets         = aws_subnet.private.*.id
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = var.app_name
    container_port   = 80
  }

  depends_on = [
    "aws_alb_listener.app_front_end"
  ]
}

### CloudWatch Logs

# Log group for the FARGATE Container
resource "aws_cloudwatch_log_group" "app" {
  name = "${aws_ecs_cluster.main.name}-${var.app_name}"
}
