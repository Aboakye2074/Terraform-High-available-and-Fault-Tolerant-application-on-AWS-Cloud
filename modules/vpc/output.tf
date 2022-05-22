output "vpc_id" {
  description = "VPC ID"
  value = aws_vpc.vpc.id
}

output "cidr_block" {
  description = "value"
  value = aws_vpc.vpc.cidr_block
}