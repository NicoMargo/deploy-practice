variable "project" {
  description = "GCP project id (per environment)"
  type        = string
}

variable "location" {
  description = "Cloud Run region"
  type        = string
}

variable "name" {
  description = "Cloud Run service name"
  type        = string
}

variable "image" {
  description = "Fully qualified container image reference"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
}

variable "env_vars" {
  description = "Environment variables injected into the container"
  type        = map(string)
  default     = {}
}
