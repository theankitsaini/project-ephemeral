# ==============================================================================
# 1. PROVIDER CONFIGURATION
# ==============================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1" # Ireland region (Free Tier eligible)
}

# ==============================================================================
# 2. CORE INFRASTRUCTURE (ECR & SECURITY)
# ==============================================================================

# Container Registry for the API
resource "aws_ecr_repository" "app_repo" {
  name                 = "amsterdam-bike-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Security Group allowing HTTP (8000) and SSH (22)
resource "aws_security_group" "ec2_sg" {
  name        = "ephemeral-project-sg"
  description = "Allow inbound traffic for web and management"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
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

# ==============================================================================
# 3. COMPUTE (EC2 & K3s)
# ==============================================================================

# EC2 Instance running K3s
resource "aws_instance" "k3s_server" {
  ami           = "ami-0905a3c97561e0b69" # Ubuntu 22.04 LTS in eu-west-1
  instance_type = "t3.micro"             # AWS Free Tier
  key_name      = "ephemeral-key"        # The SSH key pair created in AWS console

  security_groups = [aws_security_group.ec2_sg.name]

  # This tag is critical. It is what the Lambda function looks for to shut it down.
  tags = {
    Name        = "Ephemeral-Dev-Server"
    Environment = "Ephemeral-Project" 
  }

  # Automated K3s installation on startup
  user_data = <<-EOF
              #!/bin/bash
              curl -sfL https://get.k3s.io | sh -
              sudo chmod 644 /etc/rancher/k3s/k3s.yaml
              EOF
}

# Output the IP address to the terminal so you don't have to hunt for it in the console
output "ec2_public_ip" {
  description = "The public IP address of the K3s server"
  value       = aws_instance.k3s_server.public_ip
}

# ==============================================================================
# 4. FINOPS AUTOMATION (LAMBDA & IAM)
# ==============================================================================

# Zip up the local python script automatically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../scripts/lambda_handler.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Create the IAM Role that Lambda will assume
resource "aws_iam_role" "lambda_ec2_role" {
  name = "ephemeral-lambda-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Create the Policy that allows stopping and describing EC2 instances
resource "aws_iam_policy" "lambda_ec2_policy" {
  name        = "ephemeral-lambda-ec2-policy"
  description = "Allows Lambda to describe and stop tagged EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances" 
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach the Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_ec2_role.name
  policy_arn = aws_iam_policy.lambda_ec2_policy.arn
}

# Deploy the Lambda Function using the zipped code and IAM role
resource "aws_lambda_function" "ec2_shutdown_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ephemeral-ec2-stop-automation"
  role             = aws_iam_role.lambda_ec2_role.arn
  handler          = "lambda_handler.lambda_handler" 
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10 
}