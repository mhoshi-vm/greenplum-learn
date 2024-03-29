#cloud-config
runcmd:
  - |
    set -x
    export HOME=/root
    echo 'export PATH=$PATH:/usr/local/pxf-gp6/bin' >> /home/gpadmin/.bashrc
    echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc

    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'

    yum -y install java-1.8.0-openjdk-1.8.0*
    pivnet download-product-files --product-slug='vmware-greenplum' --release-version='${pxf_release_version}' --product-file-id=${pxf_product_id} -d /home/gpadmin
    chmod 644 /home/gpadmin/${pxf_file_name}

    rpm -Uvh /home/gpadmin/${pxf_file_name}

    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache fast
    yum -y install docker-ce
    systemctl start docker
    usermod -aG docker gpadmin
    systemctl enable docker.service

    yum install -y lsof nc
    yum install -y tk
