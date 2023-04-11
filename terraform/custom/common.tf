variable "pivnet_api_token" {
  type = string
}
variable "pivnet_url" {
  default = "https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1"
}
variable "gpss_release_version" {
  default = "1.9.0"
}

variable "gpss_product_id" {
  default = "1442182"
}
variable "gpss_file_name" {
  default = "gpss-gpdb6-1.9.0-rhel7-x86_64.gppkg"
}

variable "pxf_release_version" {
  default = "6.24.0"
}

variable "pxf_product_id" {
  default = "1470247"
}
variable "pxf_file_name" {
  default = "pxf-gp6-6.6.0-2.el7.x86_64.rpm"
}

variable "gpcc_release_version" {
  default = "6.8.4"
}

variable "gpcc_product_id" {
  default = "1414098"
}
variable "gpcc_file_name" {
  default = "greenplum-cc-web-6.8.4-gp6-rhel7-x86_64.zip"
}
