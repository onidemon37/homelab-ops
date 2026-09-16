variable "kubeconfig_path" {
  description = "Path to the kubeconfig file used to reach the pegasus (non-prod) cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context for the pegasus (non-prod) cluster"
  type        = string
  default     = "pegasus"
}

variable "bootstrap_revision" {
  description = "Bump to force a bootstrap Job re-run without changing any input content"
  type        = number
  default     = 1
}

variable "github_app_private_key_file" {
  description = "Path to the GitHub App private key PEM file used by Flux"
  type        = string
}

variable "github_app_id" {
  description = "GitHub App ID"
  type        = string
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID"
  type        = string
}
