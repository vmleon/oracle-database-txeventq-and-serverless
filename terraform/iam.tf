resource "oci_identity_dynamic_group" "function_dg" {
  compartment_id = var.tenancy_ocid
  name           = "txeventq-function-dg"
  description    = "Dynamic group for TxEventQ function"
  matching_rule  = "ALL {resource.type='fnfunc', resource.compartment.id='${var.compartment_ocid}'}"
}

resource "oci_identity_dynamic_group" "scheduler_dg" {
  compartment_id = var.tenancy_ocid
  name           = "txeventq-scheduler-dg"
  description    = "Dynamic group for Resource Scheduler"
  matching_rule  = "ALL {resource.type='resourceschedule', resource.id='${oci_resource_scheduler_schedule.function_trigger.id}'}"
}

resource "oci_identity_policy" "function_policy" {
  compartment_id = var.compartment_ocid
  name           = "txeventq-function-policy"
  description    = "Policy for TxEventQ function"

  statements = [
    "allow dynamic-group ${oci_identity_dynamic_group.function_dg.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${var.bucket_name}'",
    "allow dynamic-group ${oci_identity_dynamic_group.function_dg.name} to manage preauthenticated-requests in compartment id ${var.compartment_ocid} where target.bucket.name='${var.bucket_name}'",
    "allow dynamic-group ${oci_identity_dynamic_group.function_dg.name} to use virtual-network-family in compartment id ${var.compartment_ocid}",
  ]
}

resource "oci_identity_policy" "scheduler_policy" {
  compartment_id = var.compartment_ocid
  name           = "txeventq-scheduler-policy"
  description    = "Policy for Resource Scheduler to invoke function"

  statements = [
    "allow dynamic-group ${oci_identity_dynamic_group.scheduler_dg.name} to manage functions-family in compartment id ${var.compartment_ocid}",
  ]
}
