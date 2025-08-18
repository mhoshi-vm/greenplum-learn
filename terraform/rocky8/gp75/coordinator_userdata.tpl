#cloud-config
merge_how:
 - name: list
   settings: [append]
 - name: dict
   settings: [no_replace, recurse_list]
# https://networkbrouhaha.com/2022/03/cloud-init-vcd/
write_files:
- owner: gpadmin:gpadmin
  path: /home/gpadmin/gp_guc_config
  permissions: '0644'
  content: |
    ### Interconnect Settings
    gp_interconnect_queue_depth=16
    gp_interconnect_snd_queue_depth=16

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
      # coordinator has db_id 0, primary starts with db_id 1, primaries are always odd
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
    QD_PRIMARY_ARRAY=cdw~cdw~5432~/gpdata/coordinator/gpseg-1~0~-1
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
    enable_ssl = true
    # Uncomment and set the ssl_cert_file if you set enable_ssl to true.
    ssl_cert_file = /usr/local/greenplum-cc/server.pem
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

    echo "allow ${internal_cidr}" >> /etc/chrony.conf
    systemctl restart chronyd

    # Install SQUID as making the cdw node the proxy server
    dnf install epel-release -y
    dnf install squid -y
    systemctl start squid.service

    mkdir -p /tmp/complete
    chmod 777 /tmp/complete
    yum update -y

    # Check if GP6 or GP7
    GP_RELEASE_VERSION=${gp_release_version}
    GP_MAJOR_VER="$${GP_RELEASE_VERSION:0:1}"
    GPPKG_INSTALL_CMD="gppkg install -a"
    GPSYNC="gpsync"
    if [[ $${GP_MAJOR_VER} == "6" ]]; then
      sed -i 's/wal_keep_size/wal_keep_segment/g' /home/gpadmin/gp_guc_config
      GPPKG_INSTALL_CMD="gppkg --install"
      GPSYNC="gpscp"
    fi


    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}' 
    mkdir /home/gpadmin/gp_downloads/
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'greenplum-db-${gp_release_version}-*el8-*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'greenplum-db-clients-${gp_release_version}-*el8-*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'greenplum-virtual-service-*el8*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'pxf-gp'"$${GP_MAJOR_VER}"'-6*el8*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --accept-eula --product-slug='gpdb-command-center' --release-version='${gpcc_release_version}' -g 'greenplum-cc-web-*el8-*' -d /home/gpadmin/gp_downloads

    chown -R gpadmin:gpadmin /home/gpadmin/gp_downloads
    yum -y install /home/gpadmin/gp_downloads/greenplum-db-*.rpm
    yum -y install /home/gpadmin/gp_downloads/greenplum-db-clients-*.rpm
    dnf install -y /home/gpadmin/gp_downloads/greenplum-virtual-service-*el8*

    until [[ `find /tmp/complete -type f | wc -l` -eq ${seg_count} ]]
    do
      echo "waiting for segment node"
      sleep 10
    done


    rm -rf /tmp/complete

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      bash create_gpinitsystem_config.sh ${seg_count}
      gpinitsystem -a -I gpinitsystem_config -p gp_guc_config
    EOF

    # Initializing the greenplum-postmaster Service
    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      gpssh -f hosts-all "sudo mkdir -p /var/log/gpv"
      gpssh -f hosts-all "sudo chmod 777 /var/log/gpv"
      /etc/gpv/postmaster-service-initialize
      gpssh -f /home/gpadmin/hosts-all -e 'sudo usermod -a -G systemd-journal gpadmin'
    EOF

    if ls /home/gpadmin/gp_downloads/pxf*
    then
      yum -y install java-11-openjdk.x86_64

      rpm -Uvh /home/gpadmin/gp_downloads/pxf*
      echo 'export PATH=$PATH:/usr/local/pxf-gp$${GP_MAJOR_VER}/bin' >> /home/gpadmin/.bashrc
      echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
      echo 'export PXF_BASE=/usr/local/pxf-gp$${GP_MAJOR_VER}'  >> /home/gpadmin/.bashrc
      chown -R gpadmin:gpadmin /usr/local/pxf-gp$${GP_MAJOR_VER}
    fi

    echo 'export MASTER_DATA_DIRECTORY=/gpdata/coordinator/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export COORDINATOR_DATA_DIRECTORY=/gpdata/coordinator/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export PGDATABASE=template1' >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export GPCLIENT=/usr/local/greenplum-db-clients' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPCLIENT/bin:$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc

    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    # Enable GPCC
    mkdir -p /usr/local/greenplum-cc-${gpcc_release_version}
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc-${gpcc_release_version}
    ln -s /usr/local/greenplum-cc-${gpcc_release_version} /usr/local/greenplum-cc
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc

    # Add simple GPCC certs
    openssl req -newkey rsa:2048 -nodes -keyout domain.key -out domain.csr -subj "/CN=localhost"
    openssl req -key domain.key -new -x509 -days 3650 -out domain.crt -subj "/CN=localhost"

    cat domain.key >> /usr/local/greenplum-cc/server.pem
    cat domain.crt >> /usr/local/greenplum-cc/server.pem
    chown gpadmin:gpadmin /usr/local/greenplum-cc/server.pem

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      gpconfig -c shared_preload_libraries -v 'metrics_collector'
      unzip /home/gpadmin/gp_downloads/greenplum-cc-web-*.zip -d /home/gpadmin/
      cd greenplum-cc-web-${gpcc_release_version}-*
      gpstop -r -a
      ./gpccinstall-${gpcc_release_version} -c /home/gpadmin/gpcc_config
    EOF

    if ! ls /usr/local/greenplum-db-${gp_release_version}/lib/postgresql/metrics_collector.so
    then
       su - gpadmin <<EOF
         set -x
         source /usr/local/greenplum-db/greenplum_path.sh
         source /usr/local/greenplum-cc/gpcc_path.sh
         cd /usr/local/greenplum-cc/gppkg
         FILE=\`ls *${gpcc_release_version}* | tail -1\`
         $GPPKG_INSTALL_CMD \$FILE
    EOF
    fi

    su - gpadmin <<EOF
       set -x
       source /usr/local/greenplum-db/greenplum_path.sh
       source /usr/local/greenplum-cc/gpcc_path.sh
       gpcc start
    EOF

    pivnet download-product-files --accept-eula --product-slug='gpdb-data-copy' --release-version='${gpcopy_release_version}'  -g 'gpcopy-*.tar.gz' -d /home/gpadmin/gp_downloads
    tar xzvf /home/gpadmin/gp_downloads/gpcopy-*.tar.gz -C /home/gpadmin
    cp /home/gpadmin/gpcopy-*/gpcopy* /usr/local/greenplum-db/bin/
    chmod 755 /usr/local/greenplum-db/bin/gpcopy*
    chown gpadmin:gpadmin /usr/local/greenplum-db/bin/gpcopy*

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-db/greenplum_path.sh
      $GPSYNC -f hosts-segments /usr/local/greenplum-db/bin/gpcopy_helper =:/usr/local/greenplum-db/bin
    EOF

    # Enable Analytics Tools
    if [[ $${GP_MAJOR_VER} != "6" ]]
    then
        pivnet download-product-files --accept-eula --product-slug=vmware-greenplum --release-version='${gp_release_version}' -g 'DataSciencePython*el8_x86_64.gppkg' -d /home/gpadmin/gp_downloads
        su - gpadmin <<EOF
          set -x
          source /usr/local/greenplum-db/greenplum_path.sh
          $GPPKG_INSTALL_CMD gp_downloads/DataSciencePython*-el8_x86_64.gppkg
          gpconfig -c shared_preload_libraries -v 'pgml,metrics_collector'
          gpstop -r -a
    EOF

        export DSP_DIR=`ls -d /usr/local/greenplum-db/ext/DataSciencePython*`
        export DSP_LIB_DIR=`ls -d $DSP_DIR/lib/python*/site-packages`
        export DSP_LIB64_DIR=`ls -d $DSP_DIR/lib64/python*/site-packages`

        su - gpadmin <<EOF
          set -x
          source /usr/local/greenplum-db/greenplum_path.sh
          gpconfig -c pgml.venv -v $${DSP_DIR}
          gpconfig -c plpython3.python_path -v \'$${DSP_LIB_DIR}:$${DSP_LIB64_DIR}\'  --skipvalidation
          gpstop -u
    EOF

        pivnet download-product-files --accept-eula --product-slug=vmware-greenplum --release-version='${gp_release_version}' -g 'madlib*el8-x86_64.tar.gz' -d /home/gpadmin
        tar xzvf /home/gpadmin/madlib*el8-x86_64.tar.gz -C /home/gpadmin

        pivnet download-product-files --accept-eula --product-slug=vmware-greenplum --release-version='${gp_release_version}' -g 'postgis*el8-x86_64.gppkg' -d /home/gpadmin
        chmod 644 /home/gpadmin/postgis*el8-x86_64.gppkg

        su - gpadmin <<EOF
          set -x
          source /usr/local/greenplum-db/greenplum_path.sh
          $GPPKG_INSTALL_CMD /home/gpadmin/madlib*el8-x86_64/madlib*el8-x86_64.gppkg.tar.gz
          $GPPKG_INSTALL_CMD /home/gpadmin/postgis*el8-x86_64.gppkg
          gpstop -M fast -ra
    EOF

        su - gpadmin <<EOF
          set -x
          source /usr/local/greenplum-db/greenplum_path.sh
          createdb gpmlbot
          psql postgres -c "CREATE ROLE gpmlbot WITH LOGIN;"
          psql --dbname gpmlbot -c "CREATE EXTENSION plpython3u; CREATE EXTENSION madlib;"
          psql --dbname gpmlbot -c "CREATE EXTENSION IF NOT EXISTS pgml;"
          echo -e 'host \t gpmlbot \t gpmlbot \t samehost \t trust' >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf
          echo -e 'host \t gpmlbot \t gpmlbot \t 127.0.0.1/32 \t trust' >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf
          echo -e 'host \t gpmlbot \t gpmlbot \t ::1/128 \t trust' >> ${COORDINATOR_DATA_DIRECTORY}/pg_hba.conf
          gpstop -u
          gpmlbot migrate up --gphome /usr/local/greenpum-db --port 5432 --user gpadmin
          gpmlbot load-datasets --gphome /usr/local/greenpum-db --port 5432 --user gpadmin --database gpmlbot
    EOF
    fi