#cloud-config
runcmd:
  - |
    set -x
    export HOME=/root
    sleep 180
    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'

    yum -y install java-1.8.0-openjdk-1.8.0*
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${pxf_release_version}' --product-file-id=${pxf_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pxf_file_name}

    rpm -Uvh /home/gpadmin/${pxf_file_name}

    chown -R gpadmin:gpadmin /usr/local/pxf-gp*

    echo 'export PATH=$PATH:/usr/local/pxf-gp6/bin' >> /home/gpadmin/.bashrc

    su - gpadmin <<EOF
       pxf cluster register
    EOF 
