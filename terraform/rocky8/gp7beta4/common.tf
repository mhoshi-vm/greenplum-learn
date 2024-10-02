variable "pivnet_api_token" {
  type = string
}
variable "pivnet_url" {
  default = "https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1"
}

variable "pxf_release_version" {
  default = "7.0.0-beta.4"
}

variable "pxf_product_id" {
  default = "1552674"
}
variable "pxf_file_name" {
  default = "pxf-gp7-6.7.0-2.el8.x86_64.rpm"
}

variable "madlib_release_version" {
  default = "7.0.0-beta.4"
}

variable "madlib_product_id" {
  default = "1535832"
}
variable "madlib_file_name" {
  default = "madlib-2.0.0-gp7-rhel8-x86_64.tar.gz"
}

variable "plc_release_version" {
  default = "7.0.0-beta.4"
}

variable "plc_product_id" {
  default = "1521421"
}
variable "plc_file_name" {
  default = "plcontainer-2.2.1-gp7-rhel8_x86_64.gppkg"
}

variable "dspython_release_version" {
  default = "7.0.0-beta.4"
}

variable "dspython_product_id" {
  default = "1521443"
}
variable "dspython_file_name" {
  default = "DataSciencePython3.9-1.1.0-gp7-el8_x86_64.gppkg"
}

variable "postgis_release_version" {
  default = "7.0.0-beta.4"
}

variable "postgis_product_id" {
  default = "1521435"
}
variable "postgis_file_name" {
  default = "postgis-3.3.2+pivotal.1.build.1-gp7-rhel8-x86_64.gppkg"
}
