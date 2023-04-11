variable "pivnet_tar_product_id" {
  default = "1391818"
}
variable "pivnet_tar_file_name" {
  default = "gpss-gpdb6-1.8.1-photon3-x86_64.tar.gz"
}
variable "pivnet_tar_extract_file_name" {
  default = "gpss-gpdb6-1.8.1-photon3-x86_64"
}


data "template_file" "gpss_db_userfile" {
  template = "${file("gpss_db_useradata.tpl")}"

  vars = {
    pivnet_api_token = var.pivnet_api_token
    pivnet_url = var.pivnet_url
    pivnet_release_version = var.pivnet_release_version
    pivnet_tar_product_id = var.pivnet_tar_product_id
    pivnet_tar_file_name = var.pivnet_tar_file_name
    pivnet_tar_extract_file_name = var.pivnet_tar_extract_file_name
  }
}
