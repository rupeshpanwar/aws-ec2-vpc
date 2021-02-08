variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
  description = "production vpc cidr"
}

variable "public_subnet_1_cidr" {
  description = "public subnet 1 cidr"
}

variable "public_subnet_2_cidr" {
  description = "public subnet 2 cidr"
}

variable "public_subnet_3_cidr" {
  description = "public subnet 3 cidr"
}

variable "private_subnet_1_cidr" {
  description = "private subnet 1 cidr"
}


variable "private_subnet_2_cidr" {
  description = "private subnet 2 cidr"
}


variable "private_subnet_3_cidr" {
  description = "private subnet 3 cidr"
}


