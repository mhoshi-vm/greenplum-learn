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
    
    # Since you have one segment per VM and less competing workloads per VM,
    # you can set the memory limit for resource group higher than the default
    gp_resource_group_memory_limit=0.85
    
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
    wal_keep_segments=0
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
runcmd:
  - |
    set -x
    sleep 30
    export HOME=/root

    su - gpadmin <<EOF
      set -x
      bash create_gpinitsystem_config.sh ${seg_count}
      gpinitsystem -a -I gpinitsystem_config -p gp_guc_config
      gpssh -f /home/gpadmin/hosts-all "sudo systemctl enable gpdb.service"
      gpssh -f /home/gpadmin/hosts-all "sudo systemctl start gpdb.service"
      gpssh -f /home/gpadmin/hosts-all "systemctl status gpdb.service"
    EOF

    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'

    yum -y install java-1.8.0-openjdk-1.8.0*
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${pxf_release_version}' --product-file-id=${pxf_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pxf_file_name}

    rpm -Uvh /home/gpadmin/${pxf_file_name}


    echo 'export PATH=$PATH:/usr/local/pxf-gp6/bin' >> /home/gpadmin/.bashrc
    echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
    echo 'export MASTER_DATA_DIRECTORY=/gpdata/master/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc
    
    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache fast
    yum -y install docker-ce
    systemctl start docker
    usermod -aG docker gpadmin
    systemctl enable docker.service

    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${plc_release_version}' --product-file-id=${plc_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${plc_file_name}

    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${madlib_release_version}' --product-file-id=${madlib_product_id} -d /home/gpadmin
    tar xzvf /home/gpadmin/${madlib_file_name} -C /home/gpadmin

    yum install -y tk
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${dspython_release_version}' --product-file-id=${dspython_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${dspython_file_name}

    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${postgis_release_version}' --product-file-id=${postgis_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${postgis_file_name}

    su - gpadmin <<EOF
      set -x
      gppkg -i /home/gpadmin/${dspython_file_name}
      gppkg -i /home/gpadmin/${postgis_file_name}
      gppkg -i /home/gpadmin/${plc_file_name}
      gppkg -i /home/gpadmin/madlib*/${madlib_file_name}
      source /usr/local/greenplum-db/greenplum_path.sh
      gpstop -M fast -ra
    EOF
