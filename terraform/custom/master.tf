data "template_file" "master_userfile" {
  template = "${file("master_useradata.tpl")}"

  vars = {
    pivnet_api_token = var.pivnet_api_token
    pivnet_url = var.pivnet_url
    gpss_release_version = var.gpss_release_version
    gpss_product_id = var.gpss_product_id
    gpss_file_name = var.gpss_file_name
    pxf_release_version = var.pxf_release_version
    pxf_product_id = var.pxf_product_id
    pxf_file_name = var.pxf_file_name
    gpcc_release_version = var.gpcc_release_version
    gpcc_product_id = var.gpcc_product_id
    gpcc_file_name = var.gpcc_file_name
    plc_release_version = var.plc_release_version
    plc_product_id = var.plc_product_id
    plc_file_name = var.plc_file_name
    plcpy3_release_version = var.plcpy3_release_version
    plcpy3_product_id = var.plcpy3_product_id
    plcpy3_file_name = var.plcpy3_file_name
    plcpy_release_version = var.plcpy_release_version
    plcpy_product_id = var.plcpy_product_id
    plcpy_file_name = var.plcpy_file_name
  }
}


resource "vsphere_virtual_machine" "master_hosts" {
  count = local.deployment_type == "mirrored" ? 2 : 1
  name = count.index == 0 ? format("%s-mdw", var.prefix) : count.index == 1 ? format("%s-smdw", var.prefix) : format("%s-smdw-%d", var.prefix, count.index)
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
    network_id = data.vsphere_network.gp_virtual_internal_network.id
  }

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
        # master is always the first
        # standby master is always the second
        host_name = count.index == 0 ? format("mdw") : format("smdw")
        domain    = "local"
      }

      network_interface {
        ipv4_address = count.index == 0 ? local.master_internal_ip : local.standby_internal_ip
        ipv4_netmask = local.gp_virtual_internal_ipv4_netmask
      }

      network_interface {
        ipv4_address = count.index == 0 ? local.master_etl_bar_ip : local.standby_etl_bar_ip
        ipv4_netmask = local.gp_virtual_etl_bar_ipv4_netmask
      }

      network_interface {
        ipv4_address = var.gp_virtual_external_ipv4_addresses[count.index]
        ipv4_netmask = var.gp_virtual_external_ipv4_netmask
      }

      ipv4_gateway = var.gp_virtual_external_gateway
      dns_server_list = var.dns_servers
    }
  }

  vapp {
    properties = merge(data.vsphere_virtual_machine.template.vapp[0].properties ,{ "user-data" = base64encode(data.template_file.master_userfile.rendered) })
  }

}
