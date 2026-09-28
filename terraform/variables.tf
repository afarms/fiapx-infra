variable "media_bucket_name" {
  description = "Globally unique media bucket name, supplied by GitHub configuration."
  type        = string
  validation {
    condition     = can(regex("^fiapx-media-[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$", var.media_bucket_name))
    error_message = "Use fiapx-media- followed by 2 to 50 lowercase letters, digits or hyphens; end with a letter or digit."
  }
}

variable "network_availability_zones" {
  description = "Two distinct standard availability zones in us-east-1 for the demonstration environment."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  validation {
    condition = (
      length(var.network_availability_zones) == 2 &&
      length(distinct(var.network_availability_zones)) == 2 &&
      alltrue([for az in var.network_availability_zones : can(regex("^us-east-1[a-z]$", az))])
    )
    error_message = "Provide exactly two distinct availability zones in us-east-1."
  }
}
