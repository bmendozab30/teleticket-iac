variable "region" {
  description = "Region de AWS (Sao Paulo)"
  type        = string
  default     = "us-east-2"
}

variable "proyecto" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "teleticket"
}
