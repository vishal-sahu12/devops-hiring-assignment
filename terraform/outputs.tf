output "cluster_name" {
  description = "Name of the KIND cluster"
  value       = var.cluster_name
}

output "kubectl_context" {
  description = "kubectl context to access the cluster"
  value       = "kind-${var.cluster_name}"
}

output "kubectl_command" {
  description = "Command to access the KIND cluster"
  value       = "kubectl --context kind-${var.cluster_name}"
}

output "challenge_namespaces" {
  description = "Namespaces created for the challenges"
  value       = var.challenge_namespaces
}

output "cluster_nodes" {
  description = "Expected cluster nodes"
  value = {
    control_plane = "${var.cluster_name}-control-plane"
    workers       = [for i in range(1, var.worker_count + 1) : i == 1 ? "${var.cluster_name}-worker" : "${var.cluster_name}-worker${i}"]
  }
}
