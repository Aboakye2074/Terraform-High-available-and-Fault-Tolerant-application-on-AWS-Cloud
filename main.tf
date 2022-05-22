terraform {
    required_providers {
      aws = {
          source = "hashicorp/aws"
          version = "~> 3.27"
      }
    }
    required_version = ">= 0.14.9"
}

data "local_file" "assumeRole_policy" {
  filename = "policy/assumeRole_policy.json"
}

data "local_file" "policy" {
  filename = "policy/policy.json"
}

data "local_file" "bucket_policy" {
  filename = "policy/bucket_policy.json"
}

provider "aws" {
  region = var.region
  profile = "default"
  default_tags {
      tags = var.prop_tags
  }
}

module "vpc" {
  source = "./modules/vpc"
  vpc_cidr = var.cidr_block
}

# S3 bucket
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "my-simple-webpage"
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.s3_bucket.id
  acl    = "private"
}

# Bucket policy
resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.s3_bucket.id
  policy = replace(data.local_file.bucket_policy.content, "BUCKET_ARN", aws_s3_bucket.s3_bucket.arn) 
}

# Upload the code to S3
resource "aws_s3_bucket_object" "object" {
  for_each = fileset("simple-webpage/", "**")
  bucket = aws_s3_bucket.s3_bucket.bucket
  key = each.value
  source = "./simple-webpage/${each.value}"
  etag = filemd5("./simple-webpage/${each.value}")
  depends_on = [
    aws_s3_bucket.s3_bucket,
  ]
}

# Target group
resource "aws_lb_target_group" "target_group" {
  name = "targetGroup"
  port = 80
  protocol = "HTTP"
  health_check {
    path = "/health.html"
    port = 80
    protocol = "HTTP"
  }
  vpc_id = module.vpc.vpc_id #lookup(var.vpc_id, var.environment)
}

# launch configuration
resource "aws_launch_configuration" "launch_configuration" {
  name_prefix = "demo_launch_configuration"
  image_id = var.image_id
  instance_type = var.instance_type
  user_data = file("user-data.sh")
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  security_groups = [aws_security_group.private_sg.id]
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_s3_bucket_object.object, aws_nat_gateway.nat_gateway
  ]
}

# autoscaling group
resource "aws_autoscaling_group" "autoscaling_group" {
  min_size = lookup(var.asg_param, "MIN_SIZE")
  max_size = lookup(var.asg_param, "MAX_SIZE")
  desired_capacity = lookup(var.asg_param, "DESIRED_SIZE")
  health_check_grace_period = 300
  health_check_type = "ELB"
  launch_configuration = aws_launch_configuration.launch_configuration.name
  vpc_zone_identifier = values(aws_subnet.private).*.id 
  tags = [var.prop_tags]
}

#attachment
resource "aws_autoscaling_attachment" "attachment" {
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.id
  alb_target_group_arn   = aws_lb_target_group.target_group.arn
}

# Load Balancer
resource "aws_lb" "loadbalancer" {
  name = "loadBalancer-terraform"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.public_sg_lb.id]
  subnets = values(aws_subnet.public).*.id 
}

# Listener to forward HTTP request on port 80 to the target group
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.loadbalancer.arn
  port = "80"
  protocol = "HTTP"
  default_action {
      type = "forward"
      target_group_arn = aws_lb_target_group.target_group.arn
  }
}

# public subnets
resource "aws_subnet" "public" {
  for_each = var.public_zones
  vpc_id = module.vpc.vpc_id
  availability_zone = join("", [var.region, each.key])
  cidr_block = cidrsubnet(module.vpc.cidr_block, 4, each.value)
  tags = {
    Name = join("-", ["public",each.key])
  }
}

# private subnets
resource "aws_subnet" "private" {
  for_each = var.private_zones
  vpc_id = module.vpc.vpc_id
  availability_zone = join("", [var.region, each.key])
  cidr_block = cidrsubnet(module.vpc.cidr_block, 4, each.value)
  tags = {
    Name = join("-", ["private",each.key])
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = module.vpc.vpc_id
  tags = {
    Name = "IGW"
  }
}

# Route table to Internet Gateway 
resource "aws_route_table" "public_route" {
  vpc_id = module.vpc.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "Public Route"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route.id
}

# Elastic IP
resource "aws_eip" "eip" {
  vpc = true
  tags = {
    Name = "EIP - Terraform"
  }
}

# Nat Gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags = {
    Name = "gw NAT"
  }
  depends_on = [aws_internet_gateway.gw]
}

# Private route - through Nat Gateway
resource "aws_route_table" "private_route" {
  vpc_id = module.vpc.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name = "Private Route"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_route.id
}


# Security group  - instance 
resource "aws_security_group" "private_sg" {
  name = "AllowPort80Instance_Terraform"
  description = "Allow 80 access"
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg_lb.id]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = module.vpc.vpc_id 
}

# Security group  - LB 
resource "aws_security_group" "public_sg_lb" {
  name = "AllowPort80LB_Terraform"
  description = "Allow LB 80 access"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = module.vpc.vpc_id 
}

# Auto-Scaling policies
resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale_down_policy"
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_description   = "Monitor the CPU Utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]
  alarm_name          = "alb_scale_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = lookup(var.asg_param, "SCALE_DOWN_THRESHOLD")
  evaluation_periods  = "2"
  period              = "120"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }
}

resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale_up_policy"
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_description   = "Monitor the CPU Utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]
  alarm_name          = "alb_scale_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = lookup(var.asg_param, "SCALE_UP_THRESHOLD")
  evaluation_periods  = "2"
  period              = "120"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }
}


# IAM
resource "aws_iam_role" "assumeRole_policy" {
  name = "SSMEC2Role_For_Terraform"
  assume_role_policy = data.local_file.assumeRole_policy.content
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ssm_policy"
  role = aws_iam_role.assumeRole_policy.id
  policy = data.local_file.policy.content
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "instance_profileEc2"
  role = aws_iam_role.assumeRole_policy.name
}
