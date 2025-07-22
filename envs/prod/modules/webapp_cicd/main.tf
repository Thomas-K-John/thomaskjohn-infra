# CI/CD pipeline for deploying the frontend of Thomas K. John's portfolio site

# Artifact bucket for pipeline
resource "aws_s3_bucket" "artifact_bucket" {
  bucket        = "${var.bucket_name}-artifacts"
  force_destroy = true
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role-${var.bucket_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codepipeline.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Inline policy: allow CodePipeline actions
resource "aws_iam_role_policy" "codepipeline_role_policy" {
  name = "CodePipelineFullAccess"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["codepipeline:*", "s3:*"],
        Resource = "*"
      }
    ]
  })
}

# Inline policy: allow using CodeStar connection
resource "aws_iam_role_policy" "allow_codestar_connections_use" {
  name = "Allow_CodeStarConnections_Use"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "codestar-connections:UseConnection"
        ],
        Resource = [var.codestar_connection_arn]
      }
    ]
  })
}

# Inline policy: allow S3 access for artifact and website bucket
resource "aws_iam_role_policy" "allow_s3_artifact_and_website" {
  name = "Allow_S3_Artifact_and_Website"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:*"
        ],
        Resource = [
          aws_s3_bucket.artifact_bucket.arn,
          "${aws_s3_bucket.artifact_bucket.arn}/*",
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

# CodePipeline definition
resource "aws_codepipeline" "s3_deploy_pipeline" {
  name     = "DeployPipeline-${var.bucket_name}-Webapp"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = "test-branch"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToS3"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        BucketName = var.bucket_name
        Extract    = "true"
      }
    }
  }
}
