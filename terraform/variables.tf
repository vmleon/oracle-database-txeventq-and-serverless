variable "tenancy_ocid" {
  description = "OCID of the tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR block for VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "adb_db_name" {
  description = "Autonomous Database name"
  type        = string
  default     = "txeventqdb"
}

variable "adb_display_name" {
  description = "Autonomous Database display name"
  type        = string
  default     = "TxEventQ DB"
}

variable "adb_admin_password" {
  description = "Admin password for Autonomous Database"
  type        = string
  sensitive   = true
}

variable "adb_wallet_password" {
  description = "Wallet password for Autonomous Database"
  type        = string
  sensitive   = true
}

variable "bucket_name" {
  description = "Object Storage bucket name"
  type        = string
  default     = "txeventq-reports"
}

variable "queue_name" {
  description = "TxEventQ queue name"
  type        = string
  default     = "REPORT_QUEUE"
}

variable "batch_size" {
  description = "Batch size for message processing"
  type        = string
  default     = "5"
}

variable "par_validity_days" {
  description = "PAR validity period in days"
  type        = string
  default     = "7"
}

variable "smtp_host" {
  description = "SMTP server hostname"
  type        = string
}

variable "smtp_port" {
  description = "SMTP server port"
  type        = string
  default     = "1025"
}

variable "smtp_username" {
  description = "SMTP authentication username"
  type        = string
}

variable "smtp_password" {
  description = "SMTP authentication password"
  type        = string
  sensitive   = true
}

variable "sender_email" {
  description = "Email sender address"
  type        = string
}

variable "recipient_emails" {
  description = "Comma-separated recipient emails"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "ADMIN"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "function_memory_mb" {
  description = "Function memory in MB"
  type        = number
  default     = 256
}

variable "function_timeout_seconds" {
  description = "Function timeout in seconds"
  type        = number
  default     = 180
}

variable "ocir_region" {
  description = "OCIR region key"
  type        = string
}

variable "tenancy_namespace" {
  description = "OCI tenancy namespace"
  type        = string
}

variable "ocir_repo" {
  description = "OCIR repository name"
  type        = string
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "schedule_cron_expression" {
  description = "CRON expression for function schedule (minimum 1 hour interval)"
  type        = string
  default     = "0 * * * *"  # Every hour at minute 0
}

variable "schedule_display_name" {
  description = "Display name for the resource schedule"
  type        = string
  default     = "txeventq-function-schedule"
}

variable "schedule_description" {
  description = "Description for the resource schedule"
  type        = string
  default     = "Periodic schedule to invoke TxEventQ processor function"
}
