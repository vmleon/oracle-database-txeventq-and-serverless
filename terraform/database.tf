resource "oci_database_autonomous_database" "main" {
  compartment_id           = var.compartment_ocid
  db_name                  = var.adb_db_name
  display_name             = var.adb_display_name
  admin_password           = var.adb_admin_password
  db_workload              = "OLTP"
  is_auto_scaling_enabled  = false
  cpu_core_count           = 1
  data_storage_size_in_tbs = 1
  is_free_tier             = false
  license_model            = "LICENSE_INCLUDED"
}

data "oci_database_autonomous_database_wallet" "main" {
  autonomous_database_id = oci_database_autonomous_database.main.id
  password               = var.adb_wallet_password
  base64_encode_content  = true
}
