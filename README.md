# Hosting a Dynamic Web App on AWS with Terraform Module, Docker, Amazon ECR and ECS

In this project, I used terraform to create a modular infrastructure for hosting a dynamic web application on Amazon ECS (Elastic Container Service). The project involves containerizing the web app using Docker, pushing the Docker image to Amazon ECR (Elastic Container Registry), and deploying the application to ECS.

For this project, I had to provision two providers:
1. AWS
2. Docker

```
provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {
  registry_auth {
    address = data.aws_ecr_authorization_token.token.proxy_endpoint
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}
```

### Dockerfile

```
FROM nginx:latest
WORKDIR /usr/share/nginx/html/
COPY index.html /usr/share/nginx/html/
EXPOSE 80
```

### ECR
Next, I created my ECR resource, ECR Lifecycle Policy, docker image and docker registry image.

```
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

variable "aws_ecr_repository" {
  type = string
  description = "name of the ecr resource"
  default = "darey-ecr"
}
```
![ecr](./img/8%20ecr.jpg)
![ecr](./img/9%20ecr.jpg)

### ECS

- ECS.sh

```
#!/bin/bash
echo ECS_CLUSTER=my-ecs-cluster >> /etc/ecs/ecs.config
```

- Resource

```
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "ecs-template"
  image_id      = "ami-08b5b3a93ed654d19"
  instance_type = "t2.micro"
  key_name      = "DareyNext"
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-instance"
    }
  }
  user_data = filebase64("${path.module}/ecs.sh")
}

resource "aws_autoscaling_group" "ecs_asg" {
  vpc_zone_identifier = data.aws_subnets.default.ids
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_lb" "ecs_alb" {
  name               = "ecs-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  tags = {
    Name = "ecs-alb"
  }
}

resource "aws_lb_listener" "ecs_alb_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

resource "aws_lb_target_group" "ecs_tg" {
  name        = "ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id
  health_check {
    path = "/"
  }
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "my-ecs-cluster"
}

resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "test1"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "example" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
  }
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family             = "my-ecs-task"
  network_mode       = "awsvpc"
  execution_role_arn = "arn:aws:iam::239783743771:role/ecsTaskExecutionRole"
  cpu                = 256
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name      = "darey-ecr"
      image     = "239783743771.dkr.ecr.us-east-1.amazonaws.com/darey-ecr:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "ecs_service" {
  name            = "darey-ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = 2
  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = ["sg-0811e3520bad965cc"]  # Replace with actual SG ID if needed
  }
  force_new_deployment = true
  placement_constraints {
    type = "distinctInstance"
  }
  triggers = {
    redeployment = timestamp()
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    weight            = 100
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "darey-ecr"
    container_port   = 80
  }
  depends_on = [aws_autoscaling_group.ecs_asg]
}
```
![ecs](./img/1%20ecs%20cluster.jpg)
![ecs2](./img/2%20ecs%20cluster.jpg)
![task_def](./img/3%20task%20definition.jpg)
![]


- Data.tf

```
data "aws_caller_identity" "current" {}

data "aws_ecr_authorization_token" "token" {}
```

- locals.tf

```
locals{
    tags = {
        created_by = "terraform"
    }

    aws_ecr_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
```

## main.tf

```
module "ecr" {
  source = "./modules/ecr"
  # aws_ecr_repository defaults to "darey-ecr" unless overridden here
}

module "ecs" {
  source = "./modules/ecs"
}
```

I tried several ways to build the docker image but it seemed like there was a problem with the provider.
I then created the image locally using docker before creating the code.
