provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
  }
  backend "s3" {
    bucket = "sctp-tfstate-ce13"
    key    = "yq/tfstate/coaching-18-bootstrap"
    region = "us-east-1"
    # use_lockfile = true
  }
}

# The GitHub OIDC provider already exists in the account (one per account), so look it up
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:yqyeoh*/coaching-18-infra*:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "infra_ci" {
  name               = "yq-coaching18-infra-ci"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = "us-east-1"
  prefix     = "yq-coaching18"
  services   = ["s3-service", "sqs-service"]
}

data "aws_iam_policy_document" "infra_ci" {
  # --- Terraform state ---
  statement {
    sid       = "TfStateList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::sctp-tfstate-ce13"]
  }

  statement {
    sid     = "TfStateReadWrite"
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = [
      "arn:aws:s3:::sctp-tfstate-ce13/yq/tfstate/coaching-18",
      "arn:aws:s3:::sctp-tfstate-ce13/yq/tfstate/coaching-18.tflock",
    ]
  }

  # --- App resources: full control, but only on resources with our prefix ---
  statement {
    sid     = "UploadBucket"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.prefix}-uploads",
      "arn:aws:s3:::${local.prefix}-uploads/*",
    ]
  }

  statement {
    sid       = "Queue"
    actions   = ["sqs:*"]
    resources = ["arn:aws:sqs:${local.region}:${local.account_id}:${local.prefix}-*"]
  }

  statement {
    sid       = "Ecr"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prefix}-*"]
  }

  # --- ECS ---
  statement {
    sid     = "EcsClusterAndServices"
    actions = ["ecs:*"]
    resources = concat(
      [
        "arn:aws:ecs:${local.region}:${local.account_id}:cluster/${local.prefix}-ecs",
        "arn:aws:ecs:${local.region}:${local.account_id}:service/${local.prefix}-ecs/*",
      ],
      [for s in local.services : "arn:aws:ecs:${local.region}:${local.account_id}:task-definition/${s}:*"]
    )
  }

  statement {
    sid = "EcsTaskDefinitions" # these actions don't support resource-level scoping
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }

  # --- IAM: only the task roles/policies the ECS module creates ---
  statement {
    sid = "EcsTaskRoles"
    actions = [
      "iam:CreateRole", "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies", "iam:ListRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:CreatePolicy", "iam:GetPolicy", "iam:DeletePolicy", "iam:TagPolicy", "iam:UntagPolicy",
      "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
    ]
    resources = flatten([for s in local.services : [
      "arn:aws:iam::${local.account_id}:role/${s}-*",
      "arn:aws:iam::${local.account_id}:policy/${s}-*",
    ]])
  }

  statement {
    sid       = "PassTaskRolesToEcs"
    actions   = ["iam:PassRole"]
    resources = [for s in local.services : "arn:aws:iam::${local.account_id}:role/${s}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "EcsServiceLinkedRole" # only needed the first time ECS is used in the account
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/ecs.amazonaws.com/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com"]
    }
  }

  # --- CloudWatch Logs ---
  statement {
    sid     = "LogGroups"
    actions = ["logs:*"]
    resources = concat(
      ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/ecs/${local.prefix}-ecs*"],
      [for s in local.services : "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/ecs/${s}*"]
    )
  }

  statement {
    sid       = "LogGroupDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # --- VPC networking: most EC2 create actions can't be scoped by ARN, so limit to region ---
  statement {
    sid = "VpcNetworking"
    actions = [
      "ec2:Describe*",
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules", "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAclEntry", "ec2:ReplaceNetworkAclEntry",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }
}

resource "aws_iam_role_policy" "infra_ci" {
  name   = "yq-coaching18-infra-ci"
  role   = aws_iam_role.infra_ci.id
  policy = data.aws_iam_policy_document.infra_ci.json
}


output "infra_ci_role_arn" {
  value = aws_iam_role.infra_ci.arn
}

# --- App deploy roles (one per app repo) ---
locals {
  apps = {
    s3-service = {
      repo = "coaching-18-s3-app"
      ecr  = "${local.prefix}-s3-app"
    }
    sqs-service = {
      repo = "coaching-18-sqs-app"
      ecr  = "${local.prefix}-sqs-app"
    }
  }
}

data "aws_iam_policy_document" "app_trust" {
  for_each = local.apps

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:yqyeoh*/${each.value.repo}*:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_deploy" {
  for_each = local.apps

  name               = "${local.prefix}-${each.key}-deploy"
  assume_role_policy = data.aws_iam_policy_document.app_trust[each.key].json
}

data "aws_iam_policy_document" "app_deploy" {
  for_each = local.apps

  statement {
    sid       = "EcrLogin" # doesn't support resource-level scoping
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/${each.value.ecr}"]
  }

  statement {
    sid       = "EcsTaskDefinition" # doesn't support resource-level scoping
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "EcsDeploy"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:service/${local.prefix}-ecs/${each.key}"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "app_deploy" {
  for_each = local.apps

  name   = "${local.prefix}-${each.key}-deploy"
  role   = aws_iam_role.app_deploy[each.key].id
  policy = data.aws_iam_policy_document.app_deploy[each.key].json
}

output "app_deploy_role_arns" {
  value = { for k, r in aws_iam_role.app_deploy : k => r.arn }
}
