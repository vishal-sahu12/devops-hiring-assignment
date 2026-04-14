variable "cluster_name" {
  description = "Name of the KIND cluster"
  type        = string
  default     = "sanjay-challenge"
}

variable "challenge_namespaces" {
  description = "Namespaces to create for each challenge"
  type        = list(string)
  default     = ["t2", "t3", "t5", "t6"]
}

variable "kind_config_path" {
  description = "Path to KIND cluster configuration file"
  type        = string
  default     = "../kubernetes/kind-config.yaml"
}

variable "worker_count" {
  description = "Number of worker nodes in the KIND cluster"
  type        = number
  default     = 3
}
