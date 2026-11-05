# DemoBank's server: one EC2 instance running nginx, the app, and Oracle Database Free in Docker.

# The account's default network, which every AWS account has in every region
data "aws_vpc" "default" {
  default = true
}

# The latest Ubuntu 24.04 LTS image, as published by Canonical
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Firewall: SSH for you and the pipeline, HTTP for the browser. Never 1521: the database stays private.
resource "aws_security_group" "demobank" {
  name        = "demobank-${var.owner}"
  description = "DemoBank: SSH and HTTP in, everything out"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (key only). Open to all because GitHub runner addresses change"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Updates, Docker images, Python packages"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "deploy" {
  key_name   = "demobank-${var.owner}"
  public_key = file(var.public_key_path)
}

resource "aws_instance" "demobank" {
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deploy.key_name
  vpc_security_group_ids      = [aws_security_group.demobank.id]
  associate_public_ip_address = true

  # Runs once, on first boot: Docker, nginx, and the Oracle container
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "demobank-${var.owner}"
  }
}
