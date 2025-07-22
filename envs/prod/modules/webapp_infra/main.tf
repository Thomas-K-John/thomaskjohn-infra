# s3 resource configurations
resource "aws_s3_bucket" "s3_bucket" {
  bucket = local.s3_bucket_name
}

resource "aws_s3_bucket_versioning" "s3_bucket_versioning" {
  bucket = aws_s3_bucket.s3_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access" {
  bucket                  = aws_s3_bucket_versioning.s3_bucket_versioning.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_object" "s3_object" {
  for_each = { for file in local.file_list : file => file }
  bucket   = aws_s3_bucket_versioning.s3_bucket_versioning.id
  key      = each.key                            # uploads with folder structure (Eg: images/profile.jpg)
  source   = "${local.source_dir}/${each.value}" # absolute or relative path to actual file
  etag     = filemd5("${local.source_dir}/${each.value}")
  content_type = lookup(
    {
      html = "text/html"
      css  = "text/css"
      js   = "application/javascript"
      txt  = "text/plain"
      jpg  = "image/jpeg"
      jpeg = "image/jpeg"
    },
    split(".", each.value)[1],
    "binary/octet-stream"
  )
}

resource "aws_s3_bucket_website_configuration" "s3_website_configuration" {
  bucket = aws_s3_bucket_versioning.s3_bucket_versioning.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = aws_s3_bucket_versioning.s3_bucket_versioning.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.s3_bucket.arn}/*"
      }
    ]
  })
}

# Request ACM certificate
resource "aws_acm_certificate" "cert" {
  region                    = var.region
  domain_name               = local.domain_name
  subject_alternative_names = ["www.${local.domain_name}"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "TLS Certificate for ${local.domain_name}"
  }
}

# A record for root domain (thomaskjohn.com)
resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# A record for www subdomain (www.thomaskjohn.com)
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "www.${local.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# Create DNS validation record in Route 53
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

# Wait for DNS validation to complete
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# CloudFront distribution pointing to S3 website endpoint
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.s3_website_configuration.website_endpoint
    origin_id   = "S3MainOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # S3 static website hosting only supports HTTP
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "html/index.html"

  aliases = [
    local.domain_name,
    "www.${local.domain_name}"
  ]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3MainOrigin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "CloudFront for thomaskjohn.com"
  }
}
