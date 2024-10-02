data "cloudinit_config" "coordinator_config" {
  gzip          = false
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    content_type = "text/cloud-config"
    content      = templatefile("common_userdata.tpl", local.userfile_vars)
  }

  part {
    content_type = "text/cloud-config"
    content      = templatefile("coordinator_userdata.tpl", local.userfile_vars)
  }
}

resource "vsphere_virtual_machine" "coordinator_hosts" {
  count = local.deployment_type == "mirrored" ? 2 : 1
  name = count.index == 0 ? format("%s-cdw", var.prefix) : count.index == 1 ? format("%s-scdw", var.prefix) : format("%s-scdw-%d", var.prefix, count.index)
  resource_pool_id = vsphere_resource_pool.pool.id
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout = 0
  guest_id = data.vsphere_virtual_machine.template.guest_id
  firmware = data.vsphere_virtual_machine.template.firmware
  datastore_id = data.vsphere_datastore.datastore.id

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
    eagerly_scrub = local.is_thin_provision ? false : true
    thin_provisioned = local.is_thin_provision
    datastore_id = data.vsphere_datastore.datastore.id
  }

  disk {
    label = "disk1"
    size  = local.data_disk_size_in_gb
    unit_number = 1
    eagerly_scrub = local.is_thin_provision ? false : true
    thin_provisioned = local.is_thin_provision
    datastore_id = data.vsphere_datastore.datastore.id
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    customize {
      linux_options {
        # coordinator is always the first
        # standby coordinator is always the second
        host_name = count.index == 0 ? format("cdw") : format("scdw")
        domain    = "local"
      }

      network_interface {
        ipv4_address = count.index == 0 ? local.coordinator_internal_ip : local.standby_internal_ip
        ipv4_netmask = local.gp_virtual_internal_ipv4_netmask
      }

      network_interface {
        ipv4_address = count.index == 0 ? local.coordinator_etl_bar_ip : local.standby_etl_bar_ip
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

    properties = {
      "user-data" = data.cloudinit_config.coordinator_config.rendered }
  }

}
