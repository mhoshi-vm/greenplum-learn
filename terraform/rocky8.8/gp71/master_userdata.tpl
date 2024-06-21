#cloud-config

# https://networkbrouhaha.com/2022/03/cloud-init-vcd/
write_files:
- owner: gpadmin:gpadmin
  path: /home/gpadmin/gp_guc_config
  permissions: '0644'
  content: |
    ### Interconnect Settings
    gp_interconnect_queue_depth=16
    gp_interconnect_snd_queue_depth=16
    
    # This value should be 5% of the total RAM on the VM
    statement_mem=460MB
    
    # This value should be set to 25% of the total RAM on the VM
    max_statement_mem=2048MB
    
    # This value should be set to 85% of the total RAM on the VM
    gp_vmem_protect_limit=6963
    
    # Since you have less I/O bandwidth, you can turn this parameter on
    gp_workfile_compression=on
    
    # Mirrorless GUCs
    wal_level=minimal
    max_wal_senders=0
    wal_keep_size=0
    max_replication_slots=0
    gp_dispatch_keepalives_idle=20
    gp_dispatch_keepalives_interval=20
    gp_dispatch_keepalives_count=44
- owner: gpadmin:gpadmin
  path: /home/gpadmin/create_gpinitsystem_config.sh
  permissions: '0644'
  content: |
    #!/bin/bash
    # setup the gpinitsystem config
    primary_array() {
      num_primary_segments=$1
      array=""
      newline=$'\n'
      # master has db_id 0, primary starts with db_id 1, primaries are always odd
      for i in $( seq 0 $(( num_primary_segments - 1 )) ); do
        content_id=$${i}
        db_id=$(( i + 1 ))
        array+="sdw$${db_id}~sdw$${db_id}~6000~/gpdata/primary/gpseg$${content_id}~$${db_id}~$${content_id}$${newline}"
      done
      echo "$${array}"
    }
    
    create_gpinitsystem_config() {
      num_primary_segments=$1
      echo "Generate gpinitsystem"
    
    cat <<EOF> ./gpinitsystem_config
    ARRAY_NAME="Greenplum Data Platform"
    TRUSTED_SHELL=ssh
    CHECK_POINT_SEGMENTS=8
    ENCODING=UNICODE
    SEG_PREFIX=gpseg
    HEAP_CHECKSUM=on
    HBA_HOSTNAMES=0
    QD_PRIMARY_ARRAY=mdw~mdw~5432~/gpdata/master/gpseg-1~0~-1
    declare -a PRIMARY_ARRAY=(
    $( primary_array $${num_primary_segments} )
    )
    EOF
    
    }
    num_primary_segments=$1
    if [ -z "$num_primary_segments" ]; then
      echo "Usage: bash create_gpinitsystem_config.sh <num_primary_segments>"
    else
      create_gpinitsystem_config $${num_primary_segments}
    fi
- owner: root:root
  path: /root/update-etc-hosts.sh
  permissions: '0700'
  content: |
    if [ $# -ne 3 ] ; then
      echo "Usage: $0 internal_cidr segment_count offset"
      exit 1
    fi
    
    if [ ! -f /etc/hosts.bak ]; then
      cp /etc/hosts /etc/hosts.bak
    else
      cp /etc/hosts.bak /etc/hosts
    fi
    
    internal_ip_cidr=$${1}
    segment_host_count=$${2}
    offset=$${3}
    
    internal_network_ip=$(echo $${internal_ip_cidr} | cut -d"/" -f1)
    internal_netmask=$(echo $${internal_ip_cidr} | cut -d"/" -f2)
    
    if [ $${internal_netmask} -lt 20 ] && [ $${internal_netmask} -gt 24 ]; then
      echo "The CIDR should contain a netmask between 20 and 24."
      exit 1
    fi
    
    max_segment_hosts=$(( 2**(32 - internal_netmask) - 8 ))
    
    if [ $${max_segment_hosts} -lt $${segment_host_count} ]; then
      echo "ERROR: The CIDR does not have enough IPs available ($${max_segment_hosts}) to meet the VM count ($${segment_host_count})."
      exit 1
    fi
    
    octet3=$(echo $${internal_ip_cidr} | cut -d"." -f3)
    ip_prefix=$(echo $${internal_ip_cidr} | cut -d"." -f1-2)
    
    octet3_mask=$(( 256-2**(24 - internal_netmask) ))
    octet3_base=$(( octet3_mask&octet3 ))
    
    master_octet3=$(( octet3_base + 2**(24 - internal_netmask) - 1 ))

    standby_offset=$(( ${master_offset} + 1 ))
    
    master_ip="$${ip_prefix}.$${master_octet3}.${master_offset}"
    standby_ip="$${ip_prefix}.$${master_octet3}.$${standby_offset}"
    
    printf "\n$${master_ip}\tmdw\n$${standby_ip}\tsmdw\n" >> /etc/hosts
    i=$${offset}
    for hostname in $(seq -f "sdw%g" 1 $${segment_host_count}); do
      segment_internal_ip="$${ip_prefix}.$(( octet3_base + i / 256 )).$(( i % 256 ))"
      printf "$${segment_internal_ip}\t$${hostname}\n" >> /etc/hosts
      let i=i+1
    done
- owner: gpadmin:gpadmin
  path: /home/gpadmin/gpcc_config
  permissions: '0644'
  content: |
    path = /usr/local
    # Set the display_name param to the string to display in the GPCC UI.
    # The default is "gpcc"
    # display_name = gpcc

    master_port = 5432
    web_port = 28080
    rpc_port = 8899
    enable_ssl = false
    # Uncomment and set the ssl_cert_file if you set enable_ssl to true.
    # ssl_cert_file = /etc/certs/mycert
    enable_kerberos = false
    # Uncomment and set the following parameters if you set enable_kerberos to true.
    # webserver_url = <webserver_service_url>
    # krb_mode = 1
    # keytab = <path_to_keytab>
    # krb_service_name = postgres
    # User interface language: 1=English, 2=Chinese, 3=Korean, 4=Russian, 5=Japanese
    language = 5
runcmd:
  - |
    set -x
    export HOME=/root

    /root/update-etc-hosts.sh ${internal_cidr} ${seg_count} ${offset}

    # Install SQUID as making the mdw node the proxy server
    dnf install epel-release -y
    dnf install squid -y
    systemctl start squid.service

    yum update -y

    echo mdw > /home/gpadmin/hosts-all
    > /home/gpadmin/hosts-segments
    for i in {1..${seg_count}}; do
      echo "sdw$${i}" >> /home/gpadmin/hosts-all
      echo "sdw$${i}" >> /home/gpadmin/hosts-segments
    done
    chown gpadmin:gpadmin /home/gpadmin/hosts*

    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}' 
    mkdir /home/gpadmin/gp_downloads/
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'greenplum-db-${gp_release_version}-el8-*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'pxf-gp7-*el8*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --product-slug='gpdb-command-center' --release-version='${gpcc_release_version}' -g 'greenplum-cc-web-*-el8-*' -d /home/gpadmin/gp_downloads

    chown -R gpadmin:gpadmin /home/gpadmin/gp_downloads
    yum -y install /home/gpadmin/gp_downloads/greenplum-db-*.rpm

    sleep 30

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      bash create_gpinitsystem_config.sh ${seg_count}
      gpinitsystem -a -I gpinitsystem_config -p gp_guc_config
    EOF

    if ls /home/gpadmin/gp_downloads/pxf*
    then
      yum -y install java-11-openjdk.x86_64

      rpm -Uvh /home/gpadmin/gp_downloads/pxf*
      echo 'export PATH=$PATH:/usr/local/pxf-gp7/bin' >> /home/gpadmin/.bashrc
      echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
      echo 'export PXF_BASE=/usr/local/pxf-gp7'  >> /home/gpadmin/.bashrc
      chown -R gpadmin:gpadmin /usr/local/pxf-gp7
    fi

    echo 'export COORDINATOR_DATA_DIRECTORY=/gpdata/master/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc

    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    # Enable postgresml
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'DataSciencePython-*-el8_x86_64.gppkg' -d /home/gpadmin/gp_downloads

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      gppkg install -a gp_downloads/DataSciencePython3.9-*-el8_x86_64.gppkg
      gpconfig -c shared_preload_libraries -v 'pgml'
      gpstop -r -a
    EOF

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      gpconfig -c pgml.venv -v '$GPHOME/ext/DataSciencePython3.9'
      gpstop -u
    EOF

    # Enable GPCC
    mkdir -p /usr/local/greenplum-cc-${gpcc_release_version}
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc-${gpcc_release_version}
    ln -s /usr/local/greenplum-cc-${gpcc_release_version} /usr/local/greenplum-cc
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      gpconfig -c shared_preload_libraries -v 'pgml,metrics_collector'
      unzip /home/gpadmin/gp_downloads/greenplum-cc-web-*.zip -d /home/gpadmin/
      cd greenplum-cc-web-${gpcc_release_version}-gp7-el8-x86_64
      gpstop -r -a
      ./gpccinstall-${gpcc_release_version} -c /home/gpadmin/gpcc_config
    EOF

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      source /usr/local/greenplum-cc/gpcc_path.sh
      cd /usr/local/greenplum-cc/gppkg
      gppkg install -a --force MetricsCollector-${gpcc_release_version}_gp_${gp_release_version}-rocky8-x86_64.gppkg
      gpcc start
    EOF