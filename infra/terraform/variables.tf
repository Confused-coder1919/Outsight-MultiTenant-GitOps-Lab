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
