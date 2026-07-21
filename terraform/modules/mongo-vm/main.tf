locals {
    common_tags = {
        Project = var.project_name
        Environment = var.environment
        ManagedBy = "terraform"
    }
}

# 1. Ubuntu Amazon Image
data "aws_ami" "ubuntu_2004" {
    most_recent = true
    owners = ["099720109477"] # Where did Claude get this from?

    filter {
      name = "name"
      values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }

    filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 2. Security Group
resource "aws_security_group" "mongo_vm" {
  name        = "${var.project_name}-mongo-vm-sg"
  description = "Security group for MongoDB VM"
  vpc_id      = var.vpc_id

  # Intentional misconfig: SSH open to the internet (required by exercise spec)
  ingress {
    description = "SSH from anywhere (intentional misconfig)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Correctly restricted: Mongo only reachable from EKS nodes
  ingress {
    description     = "MongoDB from EKS nodes only"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mongo-vm-sg"
  })
}

# 3. Overly-permissive IAM Role
resource "aws_iam_role" "mongo_vm" {
  name = "${var.project_name}-mongo-vm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# 4. Broad EC2 Permissions
resource "aws_iam_role_policy_attachment" "mongo_vm_ec2_full" {
  role       = aws_iam_role.mongo_vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# 5. Writing Backups to S3 bucket
resource "aws_iam_role_policy" "mongo_vm_s3_backup" {
  name = "${var.project_name}-mongo-s3-backup-policy"
  role = aws_iam_role.mongo_vm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.backup_bucket_name}",
        "arn:aws:s3:::${var.backup_bucket_name}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "mongo_vm" {
  name = "${var.project_name}-mongo-vm-profile"
  role = aws_iam_role.mongo_vm.name
}

# 6. Create EC2 Instance
resource "aws_instance" "mongo_vm" {
  ami                         = data.aws_ami.ubuntu_2004.id
  instance_type               = "t3.small"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.mongo_vm.id]
  iam_instance_profile        = aws_iam_instance_profile.mongo_vm.name
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    mongo_admin_password = var.mongo_admin_password
    mongo_app_password   = var.mongo_app_password
    backup_bucket_name   = var.backup_bucket_name
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mongo-vm"
  })
}