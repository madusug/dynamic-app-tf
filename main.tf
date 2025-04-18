module "ecr" {
  source = "./modules/ecr"
  # aws_ecr_repository defaults to "darey-ecr" unless overridden here
}

module "ecs" {
  source = "./modules/ecs"
}