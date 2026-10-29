variable "region" {
  description = "Region de AWS (Sao Paulo)"
  type        = string
  default     = "sa-east-1"
}

variable "proyecto" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "teleticket"
}
