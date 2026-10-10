resource "aws_ecr_repository" "s3_app" {
  name         = "${local.prefix}-s3-app"
  force_delete = true
}

resource "aws_ecr_repository" "sqs_app" {
  name         = "${local.prefix}-sqs-app"
  force_delete = true
}

resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.prefix}-uploads"
  force_destroy = true
}

resource "aws_sqs_queue" "messages" {
  name = "${local.prefix}-queue"
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.5.0"

  cluster_name               = "${local.prefix}-ecs"
  cluster_capacity_providers = ["FARGATE"]

  services = {
    s3-service = {
      cpu                = 256
      memory             = 512
      enable_autoscaling = false

      container_definitions = {
        s3-app = {
          essential              = true
          image                  = "${aws_ecr_repository.s3_app.repository_url}:latest"
          readonlyRootFilesystem = false
          portMappings = [
            {
              containerPort = 5001
              protocol      = "tcp"
            }
          ]
          environment = [
            { name = "AWS_REGION", value = "us-east-1" },
            { name = "BUCKET_NAME", value = aws_s3_bucket.uploads.bucket }
          ]
        }
      }

      tasks_iam_role_statements = [
        {
          actions   = ["s3:PutObject"]
          resources = ["${aws_s3_bucket.uploads.arn}/*"]
        }
      ]

      assign_public_ip      = true
      subnet_ids            = module.vpc.public_subnets
      security_group_ids    = [aws_security_group.s3_app.id]
      create_security_group = false
    }

    sqs-service = {
      cpu                = 256
      memory             = 512
      enable_autoscaling = false

      container_definitions = {
        sqs-app = {
          essential              = true
          image                  = "${aws_ecr_repository.sqs_app.repository_url}:latest"
          readonlyRootFilesystem = false
          portMappings = [
            {
              containerPort = 5002
              protocol      = "tcp"
            }
          ]
          environment = [
            { name = "AWS_REGION", value = "us-east-1" },
            { name = "QUEUE_URL", value = aws_sqs_queue.messages.url }
          ]
        }
      }

      tasks_iam_role_statements = [
        {
          actions   = ["sqs:SendMessage"]
          resources = [aws_sqs_queue.messages.arn]
        }
      ]

      assign_public_ip      = true
      subnet_ids            = module.vpc.public_subnets
      security_group_ids    = [aws_security_group.sqs_app.id]
      create_security_group = false
    }
  }
}
