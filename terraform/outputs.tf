output "adb_connection_string" {
  description = "Autonomous Database connection string"
  value       = oci_database_autonomous_database.main.connection_strings[0].profiles[0].value
}

output "wallet_base64" {
  description = "Base64-encoded wallet content"
  value       = data.oci_database_autonomous_database_wallet.main.content
  sensitive   = true
}

output "function_ocid" {
  description = "Function OCID"
  value       = oci_functions_function.main.id
}

output "application_ocid" {
  description = "Function Application OCID"
  value       = oci_functions_application.main.id
}

output "bucket_name" {
  description = "Object Storage bucket name"
  value       = oci_objectstorage_bucket.main.name
}

output "namespace" {
  description = "Object Storage namespace"
  value       = data.oci_objectstorage_namespace.main.namespace
}

output "schedule_ocid" {
  description = "Resource Scheduler schedule OCID"
  value       = oci_resource_scheduler_schedule.function_trigger.id
}

output "schedule_cron" {
  description = "Resource Scheduler CRON expression"
  value       = var.schedule_cron_expression
}
