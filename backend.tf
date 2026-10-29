terraform {
  backend "s3" {
    bucket         = "teleticket-tfstate-cristian"
    key            = "terraform.tfstate"
    region         = "sa-east-1"
    encrypt        = true
  }
}