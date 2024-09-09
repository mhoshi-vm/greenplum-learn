#cloud-config
runcmd:
  - |
    set -x
    export HOME=/root

    sleep 60
    echo "proxy=http://cdw:3128" >> /etc/yum.conf
    yum update -y

    export http_proxy=http://cdw:3128
    export https_proxy=http://cdw:3128

    echo "server cdw prefer" >> /etc/chrony.conf
    systemctl restart chronyd

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
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'greenplum-db-${gp_release_version}-el8-*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'pxf-gp7-*el8*' -d /home/gpadmin/gp_downloads
    chown -R gpadmin:gpadmin /home/gpadmin/gp_downloads
    yum -y install /home/gpadmin/gp_downloads/greenplum-db-*.rpm

    if ls /home/gpadmin/gp_downloads/pxf*
    then
      yum -y install java-11-openjdk.x86_64

      rpm -Uvh /home/gpadmin/gp_downloads/pxf*

      echo 'export PATH=$PATH:/usr/local/pxf-gp7/bin' >> /home/gpadmin/.bashrc
      echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
      chown -R gpadmin:gpadmin /usr/local/pxf-gp7
    fi

    echo 'export COORDINATOR_DATA_DIRECTORY=/gpdata/coordinator/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc

    mkdir -p /usr/local/greenplum-db/etc/environment.d/
    cat <<EOF > /usr/local/greenplum-db/etc/environment.d/20-proxy.conf
    export http_proxy=http://mdw:3128
    export https_proxy=http://mdw:3128
    export no_proxy=localhost,127.0.0.1
    EOF

    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    mkdir -p /usr/local/greenplum-cc-${gpcc_release_version}
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc-${gpcc_release_version}
    ln -s /usr/local/greenplum-cc-${gpcc_release_version} /usr/local/greenplum-cc
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc
