# ---------------------------------------------------------------
# COLAS SQS (CN2, CE2, CE8, CE10)
# ---------------------------------------------------------------

# --- Cola de ordenes (FIFO) + cola de fallidos ---
resource "aws_sqs_queue" "ordenes_dlq" {
  name       = "${var.proyecto}-ordenes-dlq.fifo"
  fifo_queue = true
}

resource "aws_sqs_queue" "ordenes" {
  name       = "${var.proyecto}-ordenes.fifo"
  fifo_queue = true

  # Debe ser al menos 6 veces el timeout de Lambda Pago (60 s)
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ordenes_dlq.arn
    maxReceiveCount     = 5
  })
}

# --- Cola de correo + cola de fallidos (CE10: 5 reintentos cada 5 min) ---
resource "aws_sqs_queue" "correo_dlq" {
  name = "${var.proyecto}-correo-dlq"
}

resource "aws_sqs_queue" "correo" {
  name = "${var.proyecto}-correo"

  # 300 s = reintento cada 5 minutos
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.correo_dlq.arn
    maxReceiveCount     = 5
  })
}

# ---------------------------------------------------------------
# BASE DE DATOS: DynamoDB (CN3, CE11)
# ---------------------------------------------------------------
resource "aws_dynamodb_table" "reservas" {
  name         = "${var.proyecto}-reservas"
  billing_mode = "PAY_PER_REQUEST" # bajo demanda
  hash_key     = "asiento_id"

  attribute {
    name = "asiento_id"
    type = "S"
  }

  # Recuperacion a un punto en el tiempo 
  point_in_time_recovery {
    enabled = true
  }

  # Cifrado con llave KMS administrada por AWS (CN5)
  server_side_encryption {
    enabled = true
  }
}


# ROLES IAM: uno por funcion, con minimo privilegio (CN6)

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- Reserva: solo puede ENVIAR a la cola de ordenes ---
resource "aws_iam_role" "reserva" {
  name               = "${var.proyecto}-reserva-rol"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "reserva_logs" {
  role       = aws_iam_role.reserva.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "reserva" {
  name = "enviar-ordenes"
  role = aws_iam_role.reserva.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.ordenes.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.reservas.arn
      }
    ]
  })
}

# --- Pago: lee ordenes y deja envios en la cola de correo ---
resource "aws_iam_role" "pago" {
  name               = "${var.proyecto}-pago-rol"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "pago_logs" {
  role       = aws_iam_role.pago.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "pago" {
  name = "ordenes-y-correo"
  role = aws_iam_role.pago.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.ordenes.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.correo.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.reservas.arn
      }
    ]
  })
}

# --- Correo: solo lee la cola de correo ---
resource "aws_iam_role" "correo" {
  name               = "${var.proyecto}-correo-rol"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "correo_logs" {
  role       = aws_iam_role.correo.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "correo" {
  name = "leer-correo"
  role = aws_iam_role.correo.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.correo.arn
    }]
  })
}


# FUNCIONES LAMBDA (calculo del proyecto)

data "archive_file" "reserva" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/reserva"
  output_path = "${path.module}/build/reserva.zip"
}

data "archive_file" "pago" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/pago"
  output_path = "${path.module}/build/pago.zip"
}

data "archive_file" "correo" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/correo"
  output_path = "${path.module}/build/correo.zip"
}

# --- Lambda Reserva: timeout de 3 s (CE3) ---
resource "aws_lambda_function" "reserva" {
  function_name    = "${var.proyecto}-reserva"
  role             = aws_iam_role.reserva.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.reserva.output_path
  source_code_hash = data.archive_file.reserva.output_base64sha256
  timeout          = 3
  memory_size      = 256

  environment {
    variables = {
      COLA_ORDENES_URL = aws_sqs_queue.ordenes.url
      TABLA_RESERVAS   = aws_dynamodb_table.reservas.name
    }
  }
}

# --- Lambda Pago: timeout de 60 s (CE9) ---
resource "aws_lambda_function" "pago" {
  function_name    = "${var.proyecto}-pago"
  role             = aws_iam_role.pago.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.pago.output_path
  source_code_hash = data.archive_file.pago.output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      COLA_CORREO_URL = aws_sqs_queue.correo.url
      TABLA_RESERVAS  = aws_dynamodb_table.reservas.name
    }
  }
}

# --- Lambda Correo ---
resource "aws_lambda_function" "correo" {
  function_name    = "${var.proyecto}-correo"
  role             = aws_iam_role.correo.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.correo.output_path
  source_code_hash = data.archive_file.correo.output_base64sha256
  timeout          = 30
  memory_size      = 128
}


# DISPARADORES: la cola activa a la funcion 

resource "aws_lambda_event_source_mapping" "ordenes_a_pago" {
  event_source_arn = aws_sqs_queue.ordenes.arn
  function_name    = aws_lambda_function.pago.arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "correo_a_correo" {
  event_source_arn = aws_sqs_queue.correo.arn
  function_name    = aws_lambda_function.correo.arn
  batch_size       = 1
}


# Por ahora: 3 Lambdas, 4 colas SQS, DynamoDB.
# Se agrega después: Redis, VPC, API Gateway, pasarela de pagos real.