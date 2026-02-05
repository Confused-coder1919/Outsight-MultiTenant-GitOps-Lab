variable "VPS_IP" {
  type        = string
  description = "Public IP address of the VPS."
}

variable "VPS_USER" {
  type        = string
  description = "SSH user with sudo privileges on the VPS."
}

variable "SSH_KEY_PATH" {
  type        = string
  description = "Path to the private SSH key used to connect to the VPS."
}

variable "GITOPS_REPO" {
  type        = string
  description = "Public Git repo URL that Argo CD will sync (e.g. https://github.com/user/repo.git)."
}

variable "GITOPS_REVISION" {
  type        = string
  description = "Git revision (branch/tag/commit) Argo CD should track."
  default     = "main"
}
