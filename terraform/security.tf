resource "aws_secretsmanager_secret" "db_url" {
  name        = "pulsepay/${var.environment}/database-url"
  description = "PostgreSQL connection string for PulsePay API"
}

resource "aws_secretsmanager_secret_version" "db_url_val" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://pulsepay:prod_super_secret@rds.internal:5432/pulsepay_db"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "pulsepay-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "://amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "pulsepay-${var.environment}-read-db-secret"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db_url.arn]
    }]
  })
}
