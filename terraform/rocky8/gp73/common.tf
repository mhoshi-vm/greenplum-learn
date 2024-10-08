variable "pivnet_api_token" {
  type = string
}
variable "pivnet_url" {
  default = "https://github.com/pivotal-cf/pivnet-cli/releases/download/v4.1.1/pivnet-linux-amd64-4.1.1"
}

variable "gp_release_version" {
  default = "7.3.0"
}

variable "gpcc_release_version" {
  default = "7.1.1"
}

variable "gpcopy_release_version" {
  default = "2.7.0"
}