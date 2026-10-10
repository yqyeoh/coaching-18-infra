output "cluster_name" {
  value = module.ecs.cluster_name
}

output "s3_service_name" {
  value = module.ecs.services["s3-service"].name
}

output "sqs_service_name" {
  value = module.ecs.services["sqs-service"].name
}

output "s3_ecr_repository" {
  value = aws_ecr_repository.s3_app.name
}

output "sqs_ecr_repository" {
  value = aws_ecr_repository.sqs_app.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.uploads.bucket
}

output "sqs_queue_url" {
  value = aws_sqs_queue.messages.url
}
