data "external" "astronomy_shop_version" {
  program = ["bash", "${path.module}/scripts/resolve_astronomy_shop_version.sh", var.splunk_astronomy_shop_version]
}
