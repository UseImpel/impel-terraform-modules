terraform {
  # A floor, not a pin. These modules use precondition blocks and optional()
  # type defaults; the roots that call them require >= 1.10 anyway.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
