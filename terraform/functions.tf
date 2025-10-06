resource "oci_functions_application" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "txeventq-app"
  subnet_ids     = [oci_core_subnet.private.id]
}

resource "oci_functions_function" "main" {
  application_id = oci_functions_application.main.id
  display_name   = "txeventq-processor"
  image          = "${var.ocir_region}.ocir.io/${var.tenancy_namespace}/${var.ocir_repo}:${var.image_tag}"
  memory_in_mbs  = var.function_memory_mb
  timeout_in_seconds = var.function_timeout_seconds

  config = {
    ENVIRONMENT               = "PRODUCTION"
    QUEUE_NAME                = var.queue_name
    BATCH_SIZE                = var.batch_size
    PAR_VALIDITY_DAYS         = var.par_validity_days
    SMTP_HOST                 = var.smtp_host
    SMTP_PORT                 = var.smtp_port
    SMTP_USERNAME             = var.smtp_username
    SMTP_PASSWORD             = var.smtp_password
    SENDER_EMAIL              = var.sender_email
    RECIPIENT_EMAILS          = var.recipient_emails
    BUCKET_NAME               = var.bucket_name
    OBJECT_STORAGE_NAMESPACE  = data.oci_objectstorage_namespace.main.namespace
    DB_CONNECTION_STRING      = "jdbc:oracle:thin:@${oci_database_autonomous_database.main.db_name}_high?TNS_ADMIN=/tmp/wallet:POOLED"
    DB_USERNAME               = var.db_username
    DB_PASSWORD               = var.db_password
    WALLET_BASE64             = data.oci_database_autonomous_database_wallet.main.content
    WALLET_PASSWORD           = var.adb_wallet_password
    OCI_REGION                = var.region
  }
}
