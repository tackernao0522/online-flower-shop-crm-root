provider "aws" {
  region = var.aws_region
}

module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
  vpc_endpoints_security_group_id = module.security.vpc_endpoints_security_group_id
}

module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

# 証明書の作成を先に行う
module "dns_certificate" {
  source       = "./modules/dns_certificate"
  project_name = var.project_name
  domain_name  = var.domain_name
}

# ロードバランサーの設定
module "load_balancer" {
  source                = "./modules/load_balancer"
  project_name          = var.project_name
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  domain_name           = var.domain_name
  certificate_arn       = module.dns_certificate.certificate_arn

  depends_on = [
    module.networking,
    module.security,
    module.dns_certificate  # モジュール全体に対する依存を指定
  ]
}

# Route53レコードの作成
module "dns_records" {
  source       = "./modules/dns_records"
  domain_name  = var.domain_name
  zone_id      = module.dns_certificate.zone_id
  alb_dns_name = module.load_balancer.alb_dns_name
  alb_zone_id  = module.load_balancer.alb_zone_id

  depends_on = [module.load_balancer, module.dns_certificate]
}

# データベースの設定
module "database" {
  source               = "./modules/database"
  project_name         = var.project_name
  vpc_id               = module.networking.vpc_id
  private_subnet_ids   = module.networking.private_subnet_ids
  db_subnet_group_name = "${var.project_name}-mysql-subnet-group"
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  db_security_group_id = module.security.db_security_group_id

  depends_on = [module.networking, module.security]
}

module "secrets" {
  source = "./modules/secrets"
  
  project_name               = var.project_name
  aws_region                = var.aws_region
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  ecs_tasks_security_group_id = module.security.ecs_tasks_security_group_id
  ecs_task_role_id          = module.security.ecs_task_role_id 
  
  # シークレット値
  db_host                   = var.db_host
  db_database               = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  app_key                   = var.app_key
  jwt_secret                = var.jwt_secret
  pusher_app_id             = var.pusher_app_id
  pusher_app_key            = var.pusher_app_key
  pusher_app_secret         = var.pusher_app_secret
  aws_access_key_id         = var.aws_access_key_id
  aws_secret_access_key     = var.aws_secret_access_key
}

# コンテナサービスの設定
module "container" {
  source                = "./modules/container"
  project_name          = var.project_name
  aws_region           = var.aws_region
  domain_name          = var.domain_name
  private_subnet_ids    = module.networking.private_subnet_ids
  ecs_security_group_id = module.security.ecs_tasks_security_group_id
  ecs_execution_role_arn = module.security.ecs_execution_role_arn
  ecs_task_role_arn     = module.security.ecs_task_role_arn
  
  # Environment variables
  app_key              = var.app_key
  pusher_app_id        = var.pusher_app_id
  pusher_app_key       = var.pusher_app_key
  pusher_app_secret    = var.pusher_app_secret
  pusher_app_cluster   = var.pusher_app_cluster
  jwt_secret           = var.jwt_secret
  jwt_algo             = var.jwt_algo
  
  # Database information
  db_host              = module.database.db_endpoint
  db_name              = var.db_name
  db_username          = var.db_username
  db_password          = var.db_password
  
  # Load balancer target groups
  backend_target_group_arn  = module.load_balancer.backend_target_group_arn
  frontend_target_group_arn = module.load_balancer.frontend_target_group_arn
  websocket_target_group_arn = module.load_balancer.websocket_target_group_arn
  secrets_arn = module.secrets.secrets_arn

  depends_on = [
    module.networking,
    module.security,
    module.database,
    module.load_balancer,
    module.secrets  # 依存関係を追加
  ]
}

# モニタリングの設定
module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
  
  # Load balancer monitoring settings
  backend_target_group_arn_suffix = module.load_balancer.backend_target_group_arn_suffix
  alb_arn_suffix                 = module.load_balancer.alb_arn_suffix

  depends_on = [module.load_balancer]
}
