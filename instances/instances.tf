provider "aws" {
  region = "var.region"
}
terraform {
  backend "s3" {}
}
#connect tfstate to fetch vpc details
data "terraform_remote_state" "network-configuration" {
  backend = "s3"

  config {
      bucket = var.remote_state_bucket
      key = var.remote_state_key
      region = var.region
  }

}

#create Public SG to connect to net
resource "aws_security_group" "ec2-public-security-group" {
  name = "EC2-Public-SG"
  description = "http , ssh , Internet reaching access for Ec2 instances"
  vpc_id = data.terraform_remote_state.network-configuration.id
  #vpc_id      = "${data.terraform_remote_state.network_configuration.vpc_id}"
  ingress {
    from_port = 80
    protocol = "TCP"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    protocol = "TCP"
    to_port = 22
    cidr_blocks = ["139.167.180.101"]
  }
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#create Private SG to restrict traffic to Public SG only
resource "aws_security_group" "ec2-private-security-group" {
  name = "EC2-Private-SG"
  description = "Only allow public sg resources to access this instance and health check"
  vpc_id = data.terraform_remote_state.network-configuration.vpc_id
  ingress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    security_groups = [aws_security_group.ec2-public-security-group.id]
  }
  ingress {
    from_port = 80
    protocol = "TCP"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow health check for instance using the SG"
  }
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#create SG for ELB to allow traffic in/out
resource "aws_security_group" "elb-security-group" {
  name = "ELB-SG"
  description = "ELB Security Group"
  vpc_id = data.terraform_remote_state.network-configuration.vpc_id
  ingress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow web traffic to load balancer"
  }
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#create IAM role to allow accessing AWS service
resource "aws_iam_role" "ec2-iam-role" {
  name = "EC2-IAM-Role"
  assume_role_policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement" :
  [
    {
      "Effect" : "Allow",
      "Principal" : {
        "Service" : ["ec2.amazonaws.com", "application-autoscaling.amazonaws.com"]
      },
      "Action" : "sts:AssumeRole"
    }
  ]
}
EOF
}
#attach IAM policy
resource "aws_iam_role_policy" "ec2-iam-role-policy" {
  name = "EC2-IAM-Policy"
  role =  aws_iam_role.ec2-iam-role.id
  policy  = <<EOF
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
#create IAM Instance profile
resource "aws_iam_instance_profile" "ec2-instance-profile" {
  name = "EC2-IAM-Instance-Profile"
  role = aws_iam_role.ec2-iam-role.name
}

#EC2 Instances
#find the latest AWS AMI
data "aws_ami" "launch_configuration_ami" {
  most_recent = true

  filter {
    name = "owner-alis"
    values = ["amazon"]
  }
  owners = ["amazon"]
}
#EC2 instance (private)- launch configuration
resource "aws_launch_configuration" "ec2_private_launch_configuration" {
  image_id                    = "ami-047a51fa27710816e"
  instance_type               = var.ec2_instance_type
  key_name                    = var.key_pair_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2-instance-profile.name
  security_groups             = [aws_security_group.ec2-private-security-group.id]

  user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install httpd -y
    service httpd start
    chkconfig httpd on
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    echo "<html><body><h1>Hello from Production Backend at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}
#EC2 instance (public)- launch configuration
resource "aws_launch_configuration" "ec2_public_launch_configuration" {
  image_id                    = "ami-047a51fa27710816e"
  instance_type               = var.ec2_instance_type
  key_name                    = var.key_pair_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2-instance-profile.name
  security_groups             = [aws_security_group.ec2-public-security-group.id]

  user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install httpd -y
    service httpd start
    chkconfig httpd on
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    echo "<html><body><h1>Hello from Production WebApp at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}

#Place a load balancer for WebApp- front end
resource "aws_elb" "webapp-load-balancer" {
  name = "Production-Webapp-LoadBalancer"
  internal = false
  security_groups = [aws_security_group.elb-security-group.id]
  subnets = [
    data.terraform_remote_state.network-configuration.public_subnet_1_id,
    data.terraform_remote_state.network-configuration.public_subnet_2_id,
    data.terraform_remote_state.network-configuration.public_subnet_3_id
  ]

  listener {
    instance_port = 80
    instance_protocol = "HTTP"
    lb_port = 80
    lb_protocol = "HTTP"
  }

  health_check {
    healthy_threshold = 5
    interval = 30
    target = "HTTP:/index.html"
    timeout = 10
    unhealthy_threshold = 5
  }
}
#Place a load balancer for Backend end
resource "aws_elb" "backend-load-balancer" {
  name = "Production-Backend-LoadBalancer"
  internal = true
  security_groups = [aws_security_group.elb-security-group.id]
  subnets = [
    data.terraform_remote_state.network-configuration.private_subnet_1_id,
    data.terraform_remote_state.network-configuration.private_subnet_2_id,
    data.terraform_remote_state.network-configuration.private_subnet_3_id
  ]

  listener {
    instance_port = 80
    instance_protocol = "HTTP"
    lb_port = 80
    lb_protocol = "HTTP"
  }

  health_check {
    healthy_threshold = 5
    interval = 30
    target = "HTTP:/index.html"
    timeout = 10
    unhealthy_threshold = 5
  }
}

#place auto-scaling group
#private autoscaling group
resource "aws_autoscaling_group" "ec2-private-autoscaling-group" {
  name = "Production-Backend-AutoScalingGroup"
  vpc_zone_identifier = [
    data.terraform_remote_state.network-configuration.private_subnet_1_id,
    data.terraform_remote_state.network-configuration.private_subnet_2_id,
    data.terraform_remote_state.network-configuration.private_subnet_3_id
  ]

  max_size = var.max_instance_size
  min_size = var.min_instance_size
  launch_configuration = aws_launch_configuration.ec2_private_launch_configuration.name
  health_check_type = "ELB"
  load_balancers = [aws_elb.backend-load-balancer.name]

  tag {
    key = "Name"
    propagate_at_launch = false
    value = "Backend-EC2-Instance"
  }
 tag {
   key = "Type"
   propagate_at_launch = false
   value = "Backend"
 }
}
#public autoscaling group
resource "aws_autoscaling_group" "ec2-public-autoscaling-group" {
  name = "Production-WebApp-AutoScalingGroup"
  vpc_zone_identifier = [
    data.terraform_remote_state.network-configuration.public_subnet_1_id,
    data.terraform_remote_state.network-configuration.public_subnet_2_id,
    data.terraform_remote_state.network-configuration.public_subnet_3_id
  ]

  max_size = var.max_instance_size
  min_size = var.min_instance_size
  launch_configuration = aws_launch_configuration.ec2_private_launch_configuration.name
  health_check_type = "ELB"
  load_balancers = [aws_elb.backend-load-balancer.name]

  tag {
    key = "Name"
    propagate_at_launch = false
    value = "WebApp-EC2-Instance"
  }
  tag {
    key = "Type"
    propagate_at_launch = false
    value = "WebApp"
  }
}
#Frontend webapp autoscaling policy
resource "aws_autoscaling_policy" "webapp-production-scaling-policy" {
  autoscaling_group_name = aws_autoscaling_group.ec2-public-autoscaling-group.name
  name = "Production-WebApp-AutoScaling-Policy"
  policy_type = "TragetTrackingScaling"
  min_adjustment_magnitude = 1
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 80.0
  }
}
#Backend autoscaling policy
resource "aws_autoscaling_policy" "backend-production-scaling-policy" {
  autoscaling_group_name = aws_autoscaling_group.ec2-private-autoscaling-group.name
  name = "Production-Backend-AutoScaling-Policy"
  policy_type = "TragetTrackingScaling"
  min_adjustment_magnitude = 1
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 80.0
  }
}

#Notification setting on AutoScaling
#create SNS Topic
resource "aws_sns_topic" "webapp-production-autoscaling-alert-topic" {
  display_name = "WebApp-Autoscaling-Topic"
  name = "WebApp-Autoscaling-Topic"
}
#create SMS subscription
resource "aws_sns_topic_subscription" "webapp-production-autoscaling-sms-subscription" {
  endpoint = "+917454880627"
  protocol = "sms"
  topic_arn = aws_sns_topic.webapp-production-autoscaling-alert-topic.arn
}
#create notification
resource "aws_autoscaling_notification" "webapp-production-autoscaling-notification" {
  group_names = [aws_autoscaling_group.ec2-public-autoscaling-group.name]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_ERROR"
  ]
  topic_arn = aws_sns_topic.webapp-production-autoscaling-alert-topic.arn
}









