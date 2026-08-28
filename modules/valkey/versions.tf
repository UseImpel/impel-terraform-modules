terraform {
  # A floor, not a pin. This module uses precondition blocks, optional() type
  # defaults, and Terraform's write-only resource arguments.
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
