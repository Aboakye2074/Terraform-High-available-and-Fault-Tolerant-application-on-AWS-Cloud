# ALB dns name
output "alb" {
  description = "Application Load Balancer"
  value = aws_lb.loadbalancer.dns_name
}
