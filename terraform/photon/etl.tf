variable "pivnet_etl_product_id" {
  default = "1391817"
}
variable "pivnet_etl_file_name" {
  default = "gpss-gpdb6-1.8.1-photon3-x86_64.rpm"
}


data "template_file" "etl_userfile" {
  template = "${file("etl_useradata.tpl")}"

  vars = {
    pivnet_api_token = var.pivnet_api_token
    pivnet_url = var.pivnet_url
    pivnet_release_version = var.pivnet_release_version
    pivnet_etl_product_id = var.pivnet_etl_product_id
    pivnet_etl_file_name = var.pivnet_etl_file_name
  }
}

locals {
  etl_etl_bar_ip = cidrhost(var.gp_virtual_etl_bar_ipv4_cidr, (pow(2,(32 - local.gp_virtual_etl_bar_ipv4_netmask))-1)-6)
}

resource "vsphere_virtual_machine" "etl_hosts" {
  count = 1
  name = format("%s-etl", var.prefix)
  resource_pool_id = vsphere_resource_pool.pool.id
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout = 0
  guest_id = data.vsphere_virtual_machine.template.guest_id
  datastore_id = data.vsphere_datastore.datastore.id
  storage_policy_id = data.vsphere_storage_policy.policy.id

  memory = local.memory
  memory_reservation = local.memory_reservation
  num_cpus = local.num_cpus
  cpu_share_level = "normal"
  memory_share_level = "normal"


  network_interface {
    network_id = data.vsphere_network.gp_virtual_etl_bar_network.id
  }

  network_interface {
    network_id = data.vsphere_network.gp_virtual_external_network.id
  }

  swap_placement_policy = "vmDirectory"
  enable_disk_uuid = "true"

  disk {
    label = "disk0"
    size  = local.root_disk_size_in_gb
    unit_number = 0
    eagerly_scrub = true
    thin_provisioned = false
    datastore_id = data.vsphere_datastore.datastore.id
    storage_policy_id = data.vsphere_storage_policy.policy.id
  }

  disk {
    label = "disk1"
    size  = local.data_disk_size_in_gb
    unit_number = 1
    eagerly_scrub = true
    thin_provisioned = false
    datastore_id = data.vsphere_datastore.datastore.id
    storage_policy_id = data.vsphere_storage_policy.policy.id
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    customize {
      linux_options {
        host_name = ("etl") 
        domain    = "local"
      }

      network_interface {
        ipv4_address = local.etl_etl_bar_ip
        ipv4_netmask = local.gp_virtual_etl_bar_ipv4_netmask
      }

      network_interface {
        ipv4_netmask = var.gp_virtual_external_ipv4_netmask
      }
      
      ipv4_gateway = var.gp_virtual_external_gateway
      dns_server_list = var.dns_servers
    }
  }

  vapp {
    properties = merge(data.vsphere_virtual_machine.template.vapp[0].properties ,{ "user-data" = base64encode(data.template_file.etl_userfile.rendered) })
  }

}
