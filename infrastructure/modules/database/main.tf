# データベース用サブネットグループ
resource "aws_db_subnet_group" "mysql" {
  name       = var.db_subnet_group_name
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-mysql-subnet-group"
  }
}

# MySQL RDS インスタンス
resource "aws_db_instance" "mysql" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [var.db_security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.mysql.name

  backup_retention_period = 7
  skip_final_snapshot     = true
  multi_az               = false

  tags = {
    Name = "${var.project_name}-mysql"
  }
}
