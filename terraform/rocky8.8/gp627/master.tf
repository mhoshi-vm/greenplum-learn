locals {
  master_userfile_vars = {
    master_offset = var.master_offset
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

resource "vsphere_virtual_machine" "master_hosts" {
  count = local.deployment_type == "mirrored" ? 2 : 1
  name = count.index == 0 ? format("%s-mdw", var.prefix) : count.index == 1 ? format("%s-smdw", var.prefix) : format("%s-smdw-%d", var.prefix, count.index)
  resource_pool_id = vsphere_resource_pool.pool.id
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout = 0
  guest_id = data.vsphere_virtual_machine.template.guest_id
  firmware = data.vsphere_virtual_machine.template.firmware
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
    properties = merge(data.vsphere_virtual_machine.template.vapp[0].properties ,{ "user-data" = base64encode(templatefile("master_userdata.tpl", local.master_userfile_vars)) })
  }

}
