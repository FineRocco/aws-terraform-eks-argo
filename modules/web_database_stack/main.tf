
resource "random_password" "db_master_pass" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "${var.environment}-postgres-credentials"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "dbadmin"
    password = random_password.db_master_pass.result
  })
}

resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.environment}-flask-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "${var.environment}-db-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.environment}-postgres-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t3.micro" 
  allocated_storage      = 20
  username               = "dbadmin"
  
  password               = random_password.db_master_pass.result 
  
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "${var.environment}-postgres-db"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              dnf install -y ruby wget
              cd /home/ec2-user
              wget https://aws-codedeploy-eu-west-1.s3.eu-west-1.amazonaws.com/latest/install
              chmod +x ./install
              ./install auto
              systemctl start codedeploy-agent
              systemctl enable codedeploy-agent
              EOF

  tags = {
    Name = "${var.environment}-web-server"
  }
}