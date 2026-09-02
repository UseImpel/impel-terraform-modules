terraform {
  # A floor, not a pin. This module uses precondition blocks and optional()
  # type defaults; the roots that call it require >= 1.10 anyway.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
