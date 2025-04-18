terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

resource "aws_ecr_repository" "ecr_repo" {
  name                 = var.aws_ecr_repository
  image_tag_mutability = "MUTABLE"
  force_delete = true
  
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "my_policy" {
  repository = aws_ecr_repository.ecr_repo.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep only 10 images",
        selection    = {
          countType      = "imageCountMoreThan",
          countNumber    = 10,
          tagStatus      = "tagged",
          tagPrefixList = ["prod"]
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "docker_image" "image" {
  name         = "${aws_ecr_repository.ecr_repo.repository_url}:latest"
  keep_locally = true
}

resource "docker_registry_image" "new-darey-app" {
  name          = "${aws_ecr_repository.ecr_repo.repository_url}:latest"
  keep_remotely = true
}