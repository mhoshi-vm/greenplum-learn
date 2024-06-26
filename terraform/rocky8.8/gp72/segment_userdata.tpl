#cloud-config

write_files:
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
runcmd:
  - |
    set -x
    export HOME=/root

    /root/update-etc-hosts.sh ${internal_cidr} ${seg_count} ${offset}

    sleep 60
    echo "proxy=http://mdw:3128" >> /etc/yum.conf
    yum update -y

    export http_proxy=http://mdw:3128
    export https_proxy=http://mdw:3128

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

    echo 'export COORDINATOR_DATA_DIRECTORY=/gpdata/master/gpseg-1' >> /home/gpadmin/.bashrc
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
