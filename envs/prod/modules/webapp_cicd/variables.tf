variable "github_owner" {
  description = "GitHub username or org"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for deployment"
  type        = string
}

variable "codestar_connection_arn" {
  description = "ARN of CodeStar connection to GitHub"
  type        = string
}
