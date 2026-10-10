module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.prefix}-vpc"
  cidr = "10.0.0.0/16"

  azs                     = ["us-east-1a", "us-east-1b"]
  public_subnets          = ["10.0.1.0/24", "10.0.2.0/24"]
  map_public_ip_on_launch = true
}


# Security group for the S3 upload service (port 5001)
resource "aws_security_group" "s3_app" {
  name   = "${local.prefix}-s3-app-sg"
  vpc_id = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "s3_app_http" {
  security_group_id = aws_security_group.s3_app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 5001
  to_port           = 5001
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "s3_app_all" {
  security_group_id = aws_security_group.s3_app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Security group for the SQS message service (port 5002)
resource "aws_security_group" "sqs_app" {
  name   = "${local.prefix}-sqs-app-sg"
  vpc_id = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "sqs_app_http" {
  security_group_id = aws_security_group.sqs_app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 5002
  to_port           = 5002
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "sqs_app_all" {
  security_group_id = aws_security_group.sqs_app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
