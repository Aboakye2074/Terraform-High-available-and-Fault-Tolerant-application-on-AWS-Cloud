variable "region" {
  type = string
  default = "us-east-1"
}

variable "asg_param" {
    type = map(number)
    default = {
        MIN_SIZE = 2
        MAX_SIZE = 5
        DESIRED_SIZE = 2
        SCALE_DOWN_THRESHOLD = 10
        SCALE_UP_THRESHOLD = 40
    }
}

variable "image_id" {
    type = string
  default = "ami-0fe78f0c5bf927432"
  description = "Image"
}

variable instance_type {
    description = "Instance type"
    type = string
    default = "t2.micro"
    validation {
        condition     = can(regex("^(t2.micro|t3.micro)$", var.instance_type))
        error_message = "Expected values: t2.micro ou t3.micro."
    }
}

variable "prop_tags" {
    type = map(string)
    default = {
        Project = "Auto-scaling Terraform"
        IaC = "Terraform"
    }
}

variable "cidr_block" {
  type = string
  description = "CIDR of the VPC"
  default = "10.0.0.0/17"
}

variable "public_zones" {
  description = "Public subnet"
  type = map(number)
  default = {
      "a" = 1
      "b" = 2
      "c" = 3
  }
}

variable "private_zones" {
  description = "Private subnet"
  type = map(number)
  default = {
      "a" = 4
      "b" = 5
      "c" = 6
  }
}
