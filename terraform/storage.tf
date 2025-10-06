data "oci_objectstorage_namespace" "main" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "main" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.main.namespace
  name           = var.bucket_name
  access_type    = "NoPublicAccess"
}
