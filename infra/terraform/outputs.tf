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

output "argocd_initial_admin_password_command" {
  description = "Command to retrieve the Argo CD initial admin password."
  value       = "KUBECONFIG=${local.kubeconfig_path} kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d; echo"
}

output "grafana_admin_password_command" {
  description = "Command to retrieve the Grafana admin password."
  value       = "KUBECONFIG=${local.kubeconfig_path} kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath=\"{.data.admin-password}\" | base64 -d; echo"
}
