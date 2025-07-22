module "webapp_infra" {
  source = "./modules/webapp_infra"
}

#
module "cicd_pipeline_webapp" {
  source      = "./modules/webapp_cicd"
  bucket_name = "thomaskjohn.com"
  #Replace with your actual CodeStar connection ARN.
  # You can find this in the AWS Console under Developer Tools > Connections.
  # Avoid hardcoding this in public repos — use tfvars or environment variables if needed.
  codestar_connection_arn = "arn:aws:codeconnections:<region>:<account_id>:connection/<connection-id>"
  github_owner            = "Thomas-K-John"
  github_repo             = "thomaskjohn-webapp"
}

module "visitor_counter" {
  source = "./modules/visitor_counter"
}
