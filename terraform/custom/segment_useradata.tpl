#cloud-config
runcmd:
  - |
    set -x
    export HOME=/root
    mkdir -p /usr/local/greenplum-cc-${gpcc_release_version}
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc-${gpcc_release_version}
    ln -s /usr/local/greenplum-cc-${gpcc_release_version} /usr/local/greenplum-cc

    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'

    yum -y install java-1.8.0-openjdk-1.8.0*
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${pxf_release_version}' --product-file-id=${pxf_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pxf_file_name}

    rpm -Uvh /home/gpadmin/${pxf_file_name}

    chown -R gpadmin:gpadmin /usr/local/pxf-gp*
    echo 'export PATH=$PATH:/usr/local/pxf-gp6/bin' >> /home/gpadmin/.bashrc
    echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc

    yum install -y nfs-utils
    mkdir -p /nfs
    mount 192.168.102.243:/nfs /nfs
