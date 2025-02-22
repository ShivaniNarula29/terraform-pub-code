provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Prometheus-VPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Prometheus-Internet-Gateway"
  }
}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "Public-Subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"

  tags = {
    Name = "Public-Subnet-2"
  }
}

# Private Subnets
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Private-Subnet-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Private-Subnet-2"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Public-Route-Table"
  }
}

# NAT Gateway and Route Table for Private Subnets
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "NAT-Gateway"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Private-Route-Table"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "public_sg" {
  name        = "public-security-group"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
}

resource "aws_security_group" "private_sg" {
  name        = "private-security-group"
  description = "Allow internal Kafka traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block] # Allow internal Kafka traffic within VPC
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_1.cidr_block, aws_subnet.public_2.cidr_block] # Allow SSH from public subnets
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public Instance with SSH Key
resource "aws_instance" "public_instance" {
  ami                    = "ami-0e1bed4f06a3b463d" # Replace with a valid AMI
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.public_sg.id] # FIXED LINE
  key_name               = "VMI_PUBLIC"

  tags = {
    Name = "Public-Instance"
  }
}

# Private Instance with SSH Key and user_data
resource "aws_instance" "private_instance" {
  ami                    = "ami-0e1bed4f06a3b463d" # Replace with a valid AMI
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.private_sg.id] # FIXED LINE
  key_name               = "VMI_PUBLIC"

  tags = {
    Name = "Private-Instance"
  }
  # User data script to run the installation and configuration
  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("/home/shivani-narula/Downloads/test_local_machine.pem")
      host        = self.private_ip
      # Set up SSH proxying via the Bastion host
      bastion_host        = aws_instance.public_instance.public_ip
      bastion_user        = "ubuntu"
      bastion_private_key = file("/home/shivani-narula/Downloads/test_local_machine.pem") # Same local path as above

    }
  }
}

# Load Balancer
  resource "aws_alb" "main_alb" {
  name               = "kafka-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "Kafka-ALB"
  }
}


# Output
output "public_instance_ip" {
  value = aws_instance.public_instance.public_ip
}

output "private_instance_ip" {
  value = aws_instance.private_instance.private_ip
}
