provider "aws" {
  region = var.region
}

terraform {
    backend "s3" {}
}

#create vpc
resource "aws_vpc" "production-vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
      Name = "Production-VPC"
  }
}

#create public subnet
resource "aws_subnet" "public-subnet-1" {
  cidr_block = var.public_subnet_1_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-1a"
  tags = {
    Name = "Public-Subnet-1-CIDR"
  }
}
resource "aws_subnet" "public-subnet-2" {
  cidr_block = var.public_subnet_2_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-1b"
  tags = {
    Name = "Public-Subnet-2-CIDR"
  }
}
resource "aws_subnet" "public-subnet-3" {
  cidr_block = var.public_subnet_3_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-1c"
  tags = {
    Name = "Public_Subnet-3-CIDR"
  }
}

#create private subnet
resource "aws_subnet" "private-subnet-1" {
  cidr_block = var.private_subnet_1_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-1a"
  tags = {
    Name = "Private-Subnet-1-CIDR"
  }
}
resource "aws_subnet" "private-subnet-2" {
  cidr_block = var.private_subnet_2_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-1b"
  tags = {
    Name = "Private-Subnet-2-CIDR"
  }
}
resource "aws_subnet" "private-subnet-3" {
  cidr_block = var.private_subnet_3_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-1c"
  tags = {
    Name = "Private-Subnet-3-CIDR"
  }
}

#create route table
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.production-vpc.id
  tags = {
    Name = "Public-Route-Table"
  }
}
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.production-vpc.id

  tags = {
    Name = "Private-Route-Table"
  }
}

#public route table association
resource "aws_route_table_association" "public-subnet-1-associate" {
  route_table_id = aws_route_table.public-route-table.id
  subnet_id = aws_subnet.public-subnet-1.id
}
resource "aws_route_table_association" "public-subnet-2-association" {
  route_table_id = aws_route_table.public-route-table.id
  subnet_id = aws_subnet.public-subnet-2.id
}
resource "aws_route_table_association" "public-subnet-3-association" {
  route_table_id = aws_route_table.public-route-table.id
  subnet_id = aws_subnet.public-subnet-1.id
}

#private route table association
resource "aws_route_table_association" "private-subnet-1-association" {
  route_table_id = aws_route_table.private-route-table.id
  subnet_id = aws_subnet.private-subnet-1.id
}
resource "aws_route_table_association" "private-subnet-2-association" {
  route_table_id = aws_route_table.private-route-table.id
  subnet_id = aws_subnet.private-subnet-2.id
}
resource "aws_route_table_association" "private-subnet-3-association" {
  route_table_id = aws_route_table.private-route-table.id
  subnet_id = aws_subnet.private-subnet-3.id
}

#create EIP for NAT GW
resource "aws_eip" "elastic-ip-for-nat-gw" {
  vpc = true
  associate_with_private_ip = "10.0.0.5"

  tags = {
    Name = "Production-EIP"
  }
}

#Resource mapping for private subnet to internet
#create NAT GW and map to route table
resource "aws_nat_gateway" "nat-gw" {
  allocation_id = aws_eip.elastic-ip-for-nat-gw.id
  subnet_id = aws_subnet.public-subnet-1.id

  tags = {
    Name = "Production-NAT-GW"
  }
  depends_on = [ aws_eip.elastic-ip-for-nat-gw ]
}

#map NAT GW to Route Table //to allow traffic from inside vm to internet
resource "aws_route" "nat-gw-route" {
  route_table_id = aws_route_table.private-route-table.id
  nat_gateway_id = aws_nat_gateway.nat-gw.id
  destination_cidr_block = "0.0.0.0/0"
}

#Resource mapping from public subnet to internet
#create internet gateway
resource "aws_internet_gateway" "production-igw" {
  vpc_id = aws_vpc.production-vpc.id

  tags = {
    Name = "Production-IGW"
  }
}

#create route for public subnet
resource "aws_route" "public-internet-gw-route" {
  route_table_id = aws_route_table.public-route-table.id
  gateway_id = aws_internet_gateway.production-igw.id
  destination_cidr_block = "0.0.0.0/0"
}