output "cola_ordenes_url" {
  value = aws_sqs_queue.ordenes.url
}

output "cola_correo_url" {
  value = aws_sqs_queue.correo.url
}

output "lambda_reserva" {
  value = aws_lambda_function.reserva.function_name
}

output "lambda_pago" {
  value = aws_lambda_function.pago.function_name
}

output "lambda_correo" {
  value = aws_lambda_function.correo.function_name
}
output "tabla_reservas" {
  value = aws_dynamodb_table.reservas.name
}