variable "pivnet_api_token" {
  type = string
}
variable "pivnet_url" {
  default = "https://github.com/pivotal-cf/pivnet-cli/releases/download/v4.1.1/pivnet-linux-amd64-4.1.1"
}

variable "gp_release_version" {
  default = "7.8.3"
}

variable "gpcc_release_version" {
  default = "7.7.3"
}

variable "gpcopy_release_version" {
  default = "2.8.0"
}

# PXF moved out of the vmware-greenplum release into its own product
variable "pxf_product_slug" {
  default = "greenplum-pxf"
}

variable "pxf_release_version" {
  default = "8.0.3"
}

# gptext is versioned independently from the database as well
variable "gptext_product_slug" {
  default = "greenplum-text"
}

variable "gptext_release_version" {
  default = "3.10.1"
}