variable "region" {
  default = "us-east-1"
  description = "AWS region"
}

variable "remote_state_bucket" {
  description = "Bucket Name for layer 1 remote state"
}

variable "remote_state_key" {
  description = "Key name for layer 1 remote state"
}

variable "ec2_instance_type" {
  description = "EC2 instance type to launch"
}

variable "key_pair_name" {
  default = "connective"
  description = "Keypair to consume to connect to EC2 instances"
}

variable "max_instance_size" {
  description = "Maximum number of instance to lunch"
}

variable "min_instance_size" {
  description = "Maximum number of instance to lunch"
}

