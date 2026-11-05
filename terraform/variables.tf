variable "owner" {
  description = "Your name, lower case. Used in resource names and the Owner tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.owner))
    error_message = "owner must be 2 to 21 characters: lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "public_key_path" {
  description = "The public half of your deploy key. The pipeline uses the private half."
  type        = string
  default     = "~/.ssh/demobank_deploy.pub"
}

variable "region" {
  description = "AWS region to build in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Server size. Oracle Database Free needs about 2 GB of memory, so t3.medium (4 GB) is the smallest comfortable size."
  type        = string
  default     = "t3.medium"
}
