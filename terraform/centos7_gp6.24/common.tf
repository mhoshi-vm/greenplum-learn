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

variable "gptext_release_version" {
  default = "6.24.0"
}

variable "gptext_product_id" {
  default = "1466135"
}
variable "gptext_file_name" {
  default = "greenplum-text-3.10.0-rhel7_x86_64.tar.gz"
}

variable "plc_release_version" {
  default = "6.24.0"
}

variable "plc_product_id" {
  default = "1466063"
}
variable "plc_file_name" {
  default = "plcontainer-2.2.0-gp6-rhel7_x86_64.gppkg"
}

variable "plcpy3_release_version" {
  default = "6.24.0"
}

variable "plcpy3_product_id" {
  default = "1466146"
}
variable "plcpy3_file_name" {
  default = "plcontainer-python3-image-2.1.4-gp6.tar.gz"
}

variable "plcpy_release_version" {
  default = "6.24.0"
}

variable "plcpy_product_id" {
  default = "1466141"
}
variable "plcpy_file_name" {
  default = "plcontainer-python-image-2.1.3-gp6.tar.gz"
}
