locals {
  domain_name    = "thomaskjohn.com"
  s3_bucket_name = local.domain_name
  source_dir     = "${path.module}/../../../webapp"
  file_list      = fileset(local.source_dir, "**") # recursively get all files
}
