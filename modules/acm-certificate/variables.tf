variable "domain_name" {
  description = "Primary domain the certificate is issued for. A wildcard such as *.dev.example.com covers one label only: it matches gateway.dev.example.com but neither dev.example.com itself nor a.b.dev.example.com."
  type        = string

  validation {
    condition     = can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS name, optionally prefixed with '*.' for a wildcard."
  }
}

variable "subject_alternative_names" {
  description = "Additional names on the same certificate. Each one needs its own validation record. Use this for names a wildcard cannot cover, such as the apex alongside *.dev.example.com."
  type        = list(string)
  default     = []
}
