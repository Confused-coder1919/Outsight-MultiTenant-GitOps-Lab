output "kubeconfig_path" {
  description = "Local path to the generated kubeconfig file."
  value       = local.kubeconfig_path
}

output "argocd_url" {
  description = "Argo CD server URL (NodePort)."
  value       = "https://${var.VPS_IP}:30443"
}

output "grafana_url" {
  description = "Grafana URL (NodePort)."
  value       = "http://${var.VPS_IP}:30000"
}
