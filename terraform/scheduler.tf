resource "oci_resource_scheduler_schedule" "function_trigger" {
  compartment_id     = var.compartment_ocid
  display_name       = var.schedule_display_name
  description        = var.schedule_description
  action             = "START_RESOURCE"
  recurrence_type    = "CRON"
  recurrence_details = var.schedule_cron_expression

  resources {
    id = oci_functions_function.main.id
  }
}
