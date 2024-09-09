##########################################
# terraform variables
# Please customize based on customer needs
##########################################
variable "vsphere_user" {
  type = string
}
variable "vsphere_password" {
  type = string
}

variable "vsphere_server" {
  type = string
  description = "Enter the address of the vCenter, either as an FQDN (preferred) or an IP address"
}
variable "vsphere_datacenter" {
  default = "dc"
}
variable "vsphere_compute_cluster" {
  default = "vc"
}
variable "vsphere_datastore" {
  default = "ds"
}

variable "base_vm_name" {
  description = "Base VM with vmware-tools and Greenplum installed"
  default = "greenplum-db-template-rocky8"
}
variable "resource_pool_name" {
  description= "The name of a dedicated resource pool for Greenplum VMs which will be created by Terraform"
  default = "greenplum7.2.0"
}
variable "prefix" {
  description= "A customizable prefix name for the resource pool, Greenplum VMs, and affinity rules which will be created by Terraform"
  default = "gpv72"
}
variable "gp_virtual_external_network" {
  default = "gp-virtual-external"
}
variable "gp_virtual_internal_network" {
  default = "gp-virtual-internal"
}
variable "gp_virtual_etl_bar_network" {
  default = "gp-virtual-etl-bar"
}
# gp-virtual-external network settings
variable "gp_virtual_external_ipv4_addresses" {
  type = list(string)
  description = "The routable IP addresses for cdw and scdw, in that order (skip scdw IP address for mirroless deployment)"
  default = ["192.168.100.30" , "192.168.100.130", "192.168.100.230"]
}
variable "gp_virtual_external_ipv4_netmask" {
  description = "Netmask bitcount, e.g. 24"
  default = 24
}
variable "gp_virtual_external_gateway" {
  description = "Gateway for the gp-virtual-external network, e.g. 10.0.0.1"
  default = "192.168.100.1"
}
variable "dns_servers" {
  type = list(string)
  description = "The DNS servers for the routable network, e.g. 8.8.8.8"
  default = ["8.8.8.8", "8.8.4.4"]
}

variable "gp_virtual_internal_ipv4_cidr" {
  type = string
  description = "The leading octets for the data backup (doesn't have to be routable) network IP range, e.g. '192.168.2.0/24' or '172.17.0.0/21'"
  default = "192.168.101.0/24"
}

# gp-virtual-etl-bar network settings
variable "gp_virtual_etl_bar_ipv4_cidr" {
  type = string
  description = "The leading octets for the data backup (doesn't have to be routable) network IP range, e.g. '192.168.2.0/24' or '172.17.0.0/21'"
  default = "192.168.102.0/24"
}

variable "coordinator_offset" {
  type = string
  default = 230
}

variable "deployment_type" {
  type = string
  default = "mirrorless"
}

variable "primary_segment_count" {
  type = string
  default = 2
}

variable "segment_offset" {
  type = string
  default = 170
}

variable "root_disk_size_in_gb" {
  type = string
  default = 50
}

variable "data_disk_size_in_gb" {
  type = string
  default = 32
}

variable "is_thin_provision" {
  type = bool
  default = true
}


######################
# terraform scripts
# PLEASE DO NOT CHANGE
######################
provider "vsphere" {
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

# all of these things need to be known for a deploy to work
data "vsphere_datacenter" "dc" {
  name          = var.vsphere_datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "gp_virtual_external_network" {
  name          = var.gp_virtual_external_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "gp_virtual_internal_network" {
  name          = var.gp_virtual_internal_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# vSphere distributed port group for ETL, backup and restore traffic
data "vsphere_network" "gp_virtual_etl_bar_network" {
  name          = var.gp_virtual_etl_bar_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "compute_cluster" {
  name          = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

# this points at the template created by the image folder
data "vsphere_virtual_machine" "template" {
  name          = var.base_vm_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

locals {
  gp_virtual_internal_ip_cidr = var.gp_virtual_internal_ipv4_cidr
  deployment_type = var.deployment_type
  primary_segment_count = var.primary_segment_count
  segment_count = local.deployment_type == "mirrored" ? local.primary_segment_count * 2: local.primary_segment_count
  memory = data.vsphere_virtual_machine.template.memory
  memory_reservation = data.vsphere_virtual_machine.template.memory / 2
  num_cpus = data.vsphere_virtual_machine.template.num_cpus
  root_disk_size_in_gb = var.root_disk_size_in_gb
  data_disk_size_in_gb = var.data_disk_size_in_gb
  is_thin_provision = var.is_thin_provision
  segment_gp_virtual_internal_ipv4_offset = var.segment_offset
  segment_gp_virtual_etl_bar_ipv4_offset = var.segment_offset
  gp_virtual_internal_ipv4_netmask = parseint(regex("/(\\d+)$", local.gp_virtual_internal_ip_cidr)[0], 10)
  coordinator_internal_ip = cidrhost(local.gp_virtual_internal_ip_cidr, var.coordinator_offset) 
  standby_internal_ip = cidrhost(local.gp_virtual_internal_ip_cidr, var.coordinator_offset +1)
  gp_virtual_etl_bar_ipv4_netmask = parseint(regex("/(\\d+)$", var.gp_virtual_etl_bar_ipv4_cidr)[0], 10)
  coordinator_etl_bar_ip = cidrhost(var.gp_virtual_etl_bar_ipv4_cidr, var.coordinator_offset)
  standby_etl_bar_ip = cidrhost(var.gp_virtual_etl_bar_ipv4_cidr, var.coordinator_offset +1)
  userfile_vars = {
    ssh_pub_key = tls_private_key.common_key.public_key_openssh
    ssh_priv_key = tls_private_key.common_key.private_key_openssh
    coordinator_offset = var.coordinator_offset
    seg_count = local.segment_count
    internal_cidr = local.gp_virtual_internal_ip_cidr
    offset = local.segment_gp_virtual_internal_ipv4_offset
    pivnet_api_token = var.pivnet_api_token
    pivnet_url = var.pivnet_url
    gp_release_version = var.gp_release_version
    gpcc_release_version = var.gpcc_release_version
    gpcopy_release_version = var.gpcopy_release_version
  }
}

resource "vsphere_resource_pool" "pool" {
  name                    = "${var.prefix}-${var.resource_pool_name}"
  parent_resource_pool_id = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "coordinator_vm_anti_affinity_rule" {
    count               = local.deployment_type == "mirrored" ? 1 : 0
    enabled             = true
    mandatory           = true
    compute_cluster_id  = data.vsphere_compute_cluster.compute_cluster.id
    name                = format("%s-coordinator-vm-anti-affinity-rule", var.prefix)
    virtual_machine_ids = toset(vsphere_virtual_machine.coordinator_hosts.*.id)
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "segment_vm_anti_affinity_rule" {
    count               = local.deployment_type == "mirrored" ? local.segment_count / 2 : 0
    enabled             = true
    mandatory           = true
    compute_cluster_id  = data.vsphere_compute_cluster.compute_cluster.id
    name                = format("%s-segment-vm-anti-affinity-rule-sdw%0.3d-sdw%0.3d", var.prefix, count.index*2+1, count.index*2+2)
    virtual_machine_ids = [
        element(vsphere_virtual_machine.segment_hosts.*.id, count.index*2),
        element(vsphere_virtual_machine.segment_hosts.*.id, count.index*2+1),
    ]
}

resource "tls_private_key" "common_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

