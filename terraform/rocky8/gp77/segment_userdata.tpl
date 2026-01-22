#cloud-config
merge_how:
 - name: list
   settings: [append]
 - name: dict
   settings: [no_replace, recurse_list]
runcmd:
  - |
    set -x
    export HOME=/root

    wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 0 http://cdw:3128
    echo "proxy=http://cdw:3128" >> /etc/yum.conf
    yum update -y

    export http_proxy=http://cdw:3128
    export https_proxy=http://cdw:3128

    echo "server cdw prefer" >> /etc/chrony.conf
    systemctl restart chronyd

    # Check if GP6 or GP7
    GP_RELEASE_VERSION=${gp_release_version}
    GP_MAJOR_VER="$${GP_RELEASE_VERSION:0:1}"
    GPPKG_INSTALL_CMD="gppkg install -a"
    if [[ $${GP_MAJOR_VER} == "6" ]]; then
      GPPKG_INSTALL_CMD="gppkg --install"
    fi

    wget -O /usr/local/bin/pivnet ${pivnet_url}
    chmod +x /usr/local/bin/pivnet
    pivnet login --api-token='${pivnet_api_token}'
    mkdir /home/gpadmin/gp_downloads/
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'greenplum-db-${gp_release_version}-*el8-*' -d /home/gpadmin/gp_downloads
    pivnet download-product-files --accept-eula --product-slug='vmware-greenplum' --release-version='${gp_release_version}' -g 'pxf-gp'"$${GP_MAJOR_VER}"'-6*el8*' -d /home/gpadmin/gp_downloads
    chown -R gpadmin:gpadmin /home/gpadmin/gp_downloads
    yum -y install /home/gpadmin/gp_downloads/greenplum-db-*.rpm

    # Notify completed
    su - gpadmin <<EOF
      touch `hostname`
      scp `hostname` cdw:/tmp/complete/
    EOF

    if ls /home/gpadmin/gp_downloads/pxf*
    then
      yum -y install java-11-openjdk.x86_64

      rpm -Uvh /home/gpadmin/gp_downloads/pxf*
      echo 'export GP_MAJOR_VER='"$${GP_MAJOR_VER}" >> /home/gpadmin/.bashrc
      echo 'export PATH=$PATH:/usr/local/pxf-gp$${GP_MAJOR_VER}/bin' >> /home/gpadmin/.bashrc
      echo 'export JAVA_HOME=/usr/lib/jvm/jre'  >> /home/gpadmin/.bashrc
      echo 'export PXF_BASE=/usr/local/pxf-gp$${GP_MAJOR_VER}'  >> /home/gpadmin/.bashrc
      chown -R gpadmin:gpadmin /usr/local/pxf-gp$${GP_MAJOR_VER}
    fi

    echo 'export COORDINATOR_DATA_DIRECTORY=/gpdata/coordinator/gpseg-1' >> /home/gpadmin/.bashrc
    echo 'export GPHOME=/usr/local/greenplum-db' >> /home/gpadmin/.bashrc
    echo 'export PATH=$GPHOME/bin:$PATH' >> /home/gpadmin/.bashrc
    echo 'export LD_LIBRARY_PATH=$GPHOME/lib' >> /home/gpadmin/.bashrc

    mkdir -p /usr/local/greenplum-db/etc/environment.d/
    cat <<EOF > /usr/local/greenplum-db/etc/environment.d/20-proxy.conf
    export http_proxy=http://cdw:3128
    export https_proxy=http://cdw:3128
    export no_proxy=localhost,127.0.0.1
    EOF

    chown -R gpadmin:gpadmin /usr/local/greenplum-db*
    chgrp -R gpadmin /usr/local/greenplum-db*

    mkdir -p /usr/local/greenplum-cc-${gpcc_release_version}
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc-${gpcc_release_version}
    ln -s /usr/local/greenplum-cc-${gpcc_release_version} /usr/local/greenplum-cc
    chown -R gpadmin:gpadmin /usr/local/greenplum-cc
