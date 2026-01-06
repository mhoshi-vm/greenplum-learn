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
    statement_mem=1536MB
    
    # This value should be set to 25% of the total RAM on the VM
    max_statement_mem=7680MB
    
    # This value should be set to 85% of the total RAM on the VM
    gp_vmem_protect_limit=26112
    
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
- owner: gpadmin:gpadmin
  path: /home/gpadmin/gptext_install_config_2
  permissions: '0644'
  content: |
    # FILE NAME: gptext_install_config
    GPTEXT_HOSTS="ALLSEGHOSTS"
    declare -a DATA_DIRECTORY=(/gpdata/primary /gpdata/primary)
    JAVA_OPTS="-Xms1024M -Xmx1024M"
    GPTEXT_PORT_BASE=18983
    GP_MAX_PORT_LIMIT=28983
    ZOO_CLUSTER="BINDING"
    declare -a ZOO_HOSTS=(mdw mdw mdw)
    ZOO_DATA_DIR="/gpdata/master/"
    ZOO_GPTXTNODE="gptext"
    ZOO_PORT_BASE=2188
    ZOO_MAX_PORT_LIMIT=12188

- owner: gpadmin:gpadmin
  path: /tmp/pxf-site.xml
  permissions: '0644'
  content: |
    <?xml version="1.0" encoding="UTF-8"?>
    <configuration>
        <property>
            <name>pxf.service.kerberos.principal</name>
            <value>gpadmin/_HOST@EXAMPLE.COM</value>
            <description>Kerberos principal pxf service should use. _HOST is replaced automatically with hostnames FQDN</description>
        </property>
        <property>
            <name>pxf.service.user.impersonation</name>
            <value>false</value>
            <description>End-user identity impersonation, set to true to enable, false to disable</description>
        </property>
        <property>
            <name>pxf.service.kerberos.constrained-delegation</name>
            <value>false</value>
            <description>
                Makes user impersonation work via Kerberos constrained delegation based on S4U2Self/Proxy Kerberos extension.
                This method does not require the PXF principal to be a Hadoop proxy user, but requires the S4U2 feature
                to be enabled in an Active Directory / IPA Server. Additional configuration is needed in the
                Active Directory / IPA Server to enable the PXF principal to impersonate end users.
                Set to true to enable, false to disable.
            </description>
        </property>
    
    
        <property>
            <name>pxf.fs.basePath</name>
            <value>/nfs</value>
            <description>
                Sets the base path when constructing a file URI for read and write
                operations. This property MUST be configured for any server that
                accesses a file using a file:* profile.
            </description>
        </property>
    
        <property>
            <name>pxf.ppd.hive</name>
            <value>true</value>
            <description>Specifies whether Predicate Pushdown feature is enabled for Hive profiles.</description>
        </property>
    
        <property>
            <name>pxf.sasl.connection.retries</name>
            <value>5</value>
            <description>
                Specifies the number of retries to perform when a SASL connection is refused by a Namenode
                due to 'GSS initiate failed' error.
            </description>
        </property>
    
        <property>
            <name>pxf.orc.write.timezone.utc</name>
            <value>true</value>
            <description>
                Specifies whether the PXF ORC writer should use UTC timezone when writing timestamp values.
                If set to false, the PXF ORC writer will use the local timezone of the PXF JVM instead.
            </description>
        </property>
    
        <property>
            <name>pxf.parquet.write.decimal.overflow</name>
            <value>round</value>
            <description>
                Specifies behavior of the PXF Parquet profiles when writing NUMERIC data that exceeds the maximum precision of 38. Valid values are error, round, and ignore. The default value is round.
                If set to error, an error will be reported and the transaction will fail, potentially leaving an incomplete dataset in the external system.
                If set to round, PXF will try to round and write the value, or report an error if the value cannot be rounded, potentially leaving an incomplete dataset in the external system.
                If set to ignore, PXF will write NULL instead of the value (as in previous PXF versions).
            </description>
        </property>
    
    </configuration>
runcmd:
  - |
    set -x
    sleep 30
    export HOME=/root

    su - gpadmin <<EOF
      set -x
      bash create_gpinitsystem_config.sh 2
      gpinitsystem -a -I gpinitsystem_config -p gp_guc_config
      gpssh -f /home/gpadmin/hosts-all "sudo systemctl enable gpdb.service"
      gpssh -f /home/gpadmin/hosts-all "sudo systemctl start gpdb.service"
      gpssh -f /home/gpadmin/hosts-all "systemctl status gpdb.service"
    EOF

    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'
    pivnet download-product-files --product-slug='greenplum-streaming-server' --release-version='${gpss_release_version}' --product-file-id=${gpss_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${gpss_file_name}

    yum -y install java-1.8.0-openjdk-1.8.0*
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${pxf_release_version}' --product-file-id=${pxf_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pxf_file_name}

    rpm -Uvh /home/gpadmin/${pxf_file_name}

    chown -R gpadmin:gpadmin /usr/local/pxf-gp*
    cp /usr/local/pxf-gp6/gpextable/pxf.control /usr/local/greenplum-db-6.24.0/share/postgresql/extension/pxf.control

    echo 'export PATH=$PATH:/usr/local/pxf-gp6/bin' >> /home/gpadmin/.bashrc
    echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
    echo 'export MASTER_DATA_DIRECTORY=/gpdata/master/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc
    
    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    yum install -y nfs-utils unzip
    mkdir -p /nfs
    mount 192.168.102.243:/nfs /nfs 
    mkdir -p /nfs/ex1
    echo 'Prague,Jan,101,4875.33
    Rome,Mar,87,1557.39
    Bangalore,May,317,8936.99
    Beijing,Jul,411,11600.67' > /nfs/ex1/somedata.csv

    mkdir /usr/local/pxf-gp6/servers/nfssrvcfg
    cp /tmp/pxf-site.xml /usr/local/pxf-gp6/servers/nfssrvcfg/

    mkdir -p /usr/local/greenplum-cc-${gpcc_release_version}
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc-${gpcc_release_version}
    ln -s /usr/local/greenplum-cc-${gpcc_release_version} /usr/local/greenplum-cc

    pivnet download-product-files --product-slug='gpdb-command-center' --release-version='${gpcc_release_version}' --product-file-id=${gpcc_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${gpcc_file_name}

    cat <<EOC > /home/gpadmin/gpsscfg1.json
    {
           "Gpfdist": {
               "Host": "cdw"
           }
    }
    EOC
    chown gpadmin:gpadmin /home/gpadmin/gpsscfg1.json

    su - gpadmin <<EOF
      set -x
      . /usr/local/greenplum-db/greenplum_path.sh
      gppkg -i /home/gpadmin/${gpss_file_name}
      nohup gpss -c /home/gpadmin/gpsscfg1.json &
      createdb "gpss"
      psql -d gpss -c "CREATE EXTENSION gpss"
      psql -d gpss -c "CREATE USER gpss_user WITH PASSWORD 'password'"
      psql -d gpss -c "GRANT ALL PRIVILEGES ON DATABASE gpss TO gpss_user"
      psql -d gpss -c "CREATE TABLE social_message_data(origin varchar (200),id varchar (200),text varchar (65535),lang varchar (200), names json) DISTRIBUTED BY (id)"
      psql -d gpss -c "ALTER ROLE gpss_user CREATEEXTTABLE(type = 'readable', protocol = 'gpfdist')"
      pxf cluster register
      pxf cluster sync
      pxf cluster start
      createdb "pxf"
      psql -d pxf -c "CREATE EXTENSION pxf"
      psql -d pxf -c "CREATE EXTERNAL TABLE pxf_read_nfs(location text, month text, num_orders int, total_sales float8) LOCATION ('pxf://ex1/?PROFILE=file:text&SERVER=nfssrvcfg') FORMAT 'CSV'"

      createdb "twitter"
      psql -d twitter -c "CREATE USER twitter SUPERUSER LOGIN PASSWORD 'password'"
      psql -d twitter -c "GRANT ALL PRIVILEGES ON DATABASE twitter TO twitter"
      echo 'host	twitter	twitter	0.0.0.0/0	password' >> /gpdata/master/gpseg-1/pg_hba.conf

      unzip /home/gpadmin/${gpcc_file_name} -d /home/gpadmin/
      cd greenplum-cc-web-${gpcc_release_version}-gp6-rhel7-x86_64
      gpstop -u
      ./gpccinstall-${gpcc_release_version} -c /home/gpadmin/gpcc_config
    EOF

    su - gpadmin <<EOF
      set -x
      source /usr/local/greenplum-cc/gpcc_path.sh
      gpcc start
    EOF

    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache fast
    yum -y install docker-ce
    systemctl start docker
    usermod -aG docker gpadmin
    systemctl enable docker.service

    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${plc_release_version}' --product-file-id=${plc_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${plc_file_name}
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${plcpy3_release_version}' --product-file-id=${plcpy3_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${plcpy3_file_name}
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${plcpy_release_version}' --product-file-id=${plcpy_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${plcpy_file_name}

    yum install -y lsof nc
    mkdir /usr/local/greenplum-text-3.10.0
    mkdir /usr/local/greenplum-solr
    chown gpadmin:gpadmin /usr/local/greenplum-text-3.10.0
    chmod 775 /usr/local/greenplum-text-3.10.0
    chown gpadmin:gpadmin /usr/local/greenplum-solr
    chmod 775 /usr/local/greenplum-solr

    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${gptext_release_version}' --product-file-id=${gptext_product_id} -d /home/gpadmin
    tar xzvf /home/gpadmin/${gptext_file_name} -C /home/gpadmin

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
      gppkg -i /home/gpadmin/${madlib_file_name}
      source /usr/local/greenplum-db/greenplum_path.sh
      plcontainer image-add -f /home/gpadmin/${plcpy3_file_name}
      plcontainer image-add -f /home/gpadmin/${plcpy_file_name}
      plcontainer image-list
      plcontainer runtime-add -r plc_python_shared -i pivotaldata/plcontainer_python_shared:devel -l python
      plcontainer runtime-add -r plc_python3_shared -i pivotaldata/plcontainer_python3_shared:devel -l python3
      gpstop -M fast -ra
    EOF
