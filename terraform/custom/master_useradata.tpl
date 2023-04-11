#cloud-config
runcmd:
  - |
    set -x
    export HOME=/root
    sleep 180
    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'
    pivnet download-product-files --product-slug='greenplum-streaming-server' --release-version='${gpss_release_version}' --product-file-id=${gpss_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${gpss_file_name}

    su - gpadmin <<EOF
      . /usr/local/greenplum-db/greenplum_path.sh
      gppkg -i /home/gpadmin/${gpss_file_name}
      createdb "gpss"
      psql -d gpss -c "CREATE EXTENSION gpss"
      psql -d gpss -c "CREATE USER gpss_user WITH PASSWORD 'password'"
      psql -d gpss -c "GRANT ALL PRIVILEGES ON DATABASE gpss TO gpss_user"
      psql -d gpss -c "CREATE TABLE social_message_data(origin varchar (200),id varchar (200),text varchar (65535),lang varchar (200), names json) DISTRIBUTED BY (id)"
      psql -d gpss -c "ALTER ROLE gpss_user CREATEEXTTABLE(type = 'readable', protocol = 'gpfdist')"
    EOF

    yum -y install java-1.8.0-openjdk-1.8.0*
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${pxf_release_version}' --product-file-id=${pxf_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pxf_file_name}

    rpm -Uvh /home/gpadmin/${pxf_file_name}

    chown -R gpadmin:gpadmin /usr/local/pxf-gp*

    echo 'export PATH=$PATH:/usr/local/pxf-gp6/bin' >> /home/gpadmin/.bashrc

    su - gpadmin <<EOF
       pxf cluster register
    EOF 
