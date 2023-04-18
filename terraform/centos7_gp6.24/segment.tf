data "template_file" "segment_userfile" {
  template = "${file("segment_useradata.tpl")}"

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
  }
}

resource "vsphere_virtual_machine" "segment_hosts" {
  count = local.segment_count
  name = format("%s-sdw-%0.3d", var.prefix, count.index + 1)
  resource_pool_id = vsphere_resource_pool.pool.id
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout = 0
  guest_id = data.vsphere_virtual_machine.template.guest_id
  datastore_id = data.vsphere_datastore.datastore.id
  storage_policy_id = data.vsphere_storage_policy.policy.id
  scsi_controller_count = 2

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
        host_name = "sdw${count.index + 1}"
        domain    = "local"
      }

      network_interface {
        ipv4_address = cidrhost(local.gp_virtual_internal_ip_cidr, count.index + local.segment_gp_virtual_internal_ipv4_offset)
        ipv4_netmask = local.gp_virtual_internal_ipv4_netmask
      }

      network_interface {
        ipv4_address = cidrhost(var.gp_virtual_etl_bar_ipv4_cidr, count.index + local.segment_gp_virtual_etl_bar_ipv4_offset)
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
    properties = merge(data.vsphere_virtual_machine.template.vapp[0].properties ,{ "user-data" = base64encode(data.template_file.segment_userfile.rendered) })
  }
}
