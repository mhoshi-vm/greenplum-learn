variable "pivnet_product_id" {
  default = "1391816"
}
variable "pivnet_file_name" {
  default = "gpss-gpdb6-1.8.1-photon3-x86_64.gppkg"
}


data "template_file" "gpss_master_userfile" {
  template = "${file("gpss_master_useradata.tpl")}"

  vars = {
    pivnet_api_token = var.pivnet_api_token
    pivnet_url = var.pivnet_url
    pivnet_release_version = var.pivnet_release_version
    pivnet_product_id = var.pivnet_product_id
    pivnet_file_name = var.pivnet_file_name
  }
}
