terraform {
  # A floor, not a pin. These modules use precondition blocks and optional()
  # type defaults; the roots that call them require >= 1.10 anyway.
  # secret_string_wo avoids reading generated adapter credentials during plan;
  # Terraform added write-only resource arguments in 1.11.
  required_version = ">= 1.11"

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
