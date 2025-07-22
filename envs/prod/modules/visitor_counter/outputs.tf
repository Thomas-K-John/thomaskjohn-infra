output "lambda_file_path" {
  description = "The complete path and name of the lambda function"
  value       = aws_lambda_function.lambda_function.filename
}
