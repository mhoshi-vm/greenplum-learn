#cloud-config
merge_how:
 - name: list
   settings: [append]
 - name: dict
   settings: [no_replace, recurse_list]
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca_certs
 - rsyslog
 - users_groups
 - write_files
disable_root: false
chpasswd:
  users:
  - name: gpadmin
    type: text
    password: '!QAZxsw2#EDC'
  expire: False
ssh_pwauth: True
users:
- name: gpadmin
  sudo: ALL=(ALL) NOPASSWD:ALL
  ssh_authorized_keys:
  - ${ssh_pub_key}
write_files:
- owner: gpadmin:gpadmin
  path: /home/gpadmin/.ssh/id_rsa
  permissions: '0600'
  content: "${ssh_priv_key}"
- owner: gpadmin:gpadmin
  path: /home/gpadmin/.ssh/id_rsa.pub
  permissions: '0644'
  content: ${ssh_pub_key}
- owner: gpadmin:gpadmin
  path: /home/gpadmin/.ssh/config
  permissions: '0400'
  content: |
    Host *
        StrictHostKeyChecking no
- owner: root:root
  path: /etc/sysctl.d/10-gpdb.conf
  permissions: '0644'
  content: |
    kernel.shmmni = 4096
    net.ipv4.ip_local_port_range = 10000 65535 # See Port Settings
    kernel.sem = 250 2048000 200 8192
    kernel.sysrq = 1
    kernel.core_uses_pid = 1
    kernel.msgmnb = 65536
    kernel.msgmax = 65536
    kernel.msgmni = 2048
    net.ipv4.tcp_syncookies = 1
    net.ipv4.conf.default.accept_source_route = 0
    net.ipv4.tcp_max_syn_backlog = 4096
    net.ipv4.conf.all.arp_filter = 1
    net.ipv4.ipfrag_high_thresh = 41943040
    net.ipv4.ipfrag_low_thresh = 31457280
    net.ipv4.ipfrag_time = 60
    net.core.netdev_max_backlog = 10000
    net.core.rmem_max = 2097152
    net.core.wmem_max = 2097152
    vm.swappiness = 10
    vm.zone_reclaim_mode = 0
    vm.dirty_expire_centisecs = 500
    vm.dirty_writeback_centisecs = 100

    # RAM is less than or equal to 64 GB
    vm.dirty_background_ratio = 3
    vm.dirty_ratio = 10
    # Core Dump
    kernel.core_pattern=/var/core/core.%h.%t

- owner: root:root
  path: /etc/security/limits.d/20-nproc.conf
  permissions: '0644'
  content: |
    * soft nofile 524288
    * hard nofile 524288
    * soft nproc 131072
    * hard nproc 131072
    * soft core unlimited
- owner: root:root
  path: /root/update-etc-hosts.sh
  permissions: '0700'
  content: |
    if [ $# -ne 4 ] ; then
      echo "Usage: $0 internal_cidr segment_count offset etl_bar_cdw_ip"
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
    etl_bar_cdw_ip=$${4}

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

    coordinator_octet3=$(( octet3_base + 2**(24 - internal_netmask) - 1 ))

    standby_offset=$(( ${coordinator_offset} + 1 ))

    coordinator_ip="$${ip_prefix}.$${coordinator_octet3}.${coordinator_offset}"
    standby_ip="$${ip_prefix}.$${coordinator_octet3}.$${standby_offset}"

    printf "\n$${coordinator_ip}\tcdw\n$${standby_ip}\tscdw\n" >> /etc/hosts
    printf "\n$${etl_bar_cdw_ip}\tcdw-etl\n" >> /etc/hosts

    i=$${offset}
    for hostname in $(seq -f "sdw%g" 1 $${segment_host_count}); do
      segment_internal_ip="$${ip_prefix}.$(( octet3_base + i / 256 )).$(( i % 256 ))"
      printf "$${segment_internal_ip}\t$${hostname}\n" >> /etc/hosts
      let i=i+1
    done
- owner: root:root
  path: /etc/gpv/gpdb-service
  permissions: '0744'
  content: |
    #!/bin/bash

    set -e
    echo ==========================================================
    echo [the begin timestamp is: $(date)]

    if [ -d /gpdata/coordinator/gpseg* ]; then
      POSTMASTER_FILE_PATH=$(ls -d /gpdata/coordinator/gpseg*)
      printf -v PGCTL_OPTION ' -D %s -w -t 120 -o " %s " ' $${POSTMASTER_FILE_PATH} "-E"
    elif [ -d /gpdata/primary/gpseg* ]; then
      POSTMASTER_FILE_PATH=$(ls -d /gpdata/primary/gpseg*)
      printf -v PGCTL_OPTION ' -D %s -w -t 120 ' $${POSTMASTER_FILE_PATH}
    else
      echo the current cluster might not be initialized by gpinitsystem
      echo we cannot find /gpdata/master/gpseg* or /gpdata/primary/gpseg*
      echo please double check the cluster is initialized
      echo and then restart the gpdb.service again.
      exit 1
    fi

    echo POSTMASTER_FILE_PATH is $${POSTMASTER_FILE_PATH}
    echo PGCTL_OPTION is $${PGCTL_OPTION}

    echo about to $1 ...

    case "$1" in
      start)
        if [ ! -z "$(ps -ef | grep postgres | grep gpseg)" ]; then
          echo there is an existing postmaster running by somebody else, stop it
          /usr/local/greenplum-db/bin/pg_ctl -w -D $${POSTMASTER_FILE_PATH} --mode=fast stop
        fi
        echo clean-up left-over files if any
        rm -f /tmp/.s.PGSQL.*
        rm -f $${POSTMASTER_FILE_PATH}/postmaster.pid

        echo starting new postmaster ...
        eval /usr/local/greenplum-db/bin/pg_ctl $${PGCTL_OPTION} start
        echo postmaster is started

        echo extracting postmaster pid...
        touch /home/gpadmin/.gpv.postmaster.pid
        POSTMASTER_PID=$(head -1 $${POSTMASTER_FILE_PATH}/postmaster.pid)
        echo $${POSTMASTER_PID} > /home/gpadmin/.gpv.postmaster.pid
        echo $(date) >> /home/gpadmin/.gpv.postmaster.pid
        echo remembered the postmaster pid as $${POSTMASTER_PID}
        ;;
      stop)
        echo stopping postmaster with pid $(cat /home/gpadmin/.gpv.postmaster.pid) ...
        /usr/local/greenplum-db/bin/pg_ctl -w -D $${POSTMASTER_FILE_PATH} --mode=fast stop
        echo postmaster is stopped
      ;;
      *)
        echo "Usage: $0 {start|stop}"
      esac

    echo [the end timestamp is: $(date)]
    exit 0
- owner: root:root
  path: /etc/systemd/system/gpdb.service
  permissions: '0644'
  content: |
    [Unit]
    Description=Greenplum Service

    [Service]
    Type=forking
    User=gpadmin
    LimitNOFILE=524288
    LimitNPROC=131072
    ExecStart=/bin/bash -l -c "/etc/gpv/gpdb-service start 2>&1 | tee -a /var/log/gpv/gpdb-service.log"
    ExecStop=/bin/bash -l -c "/etc/gpv/gpdb-service stop 2>&1 | tee -a /var/log/gpv/gpdb-service.log"
    TimeoutStartSec=120
    Restart=always
    PIDFile=/home/gpadmin/.gpv.postmaster.pid
    RestartSec=1s

    [Install]
    WantedBy=multi-user.target
bootcmd:
  - |
    set -x
    export HOME=/root
    export REBOOT=0

    if ! grubby --info=0 | egrep -qw "elevator=deadline"
    then
      grubby --update-kernel=ALL --args="elevator=deadline"
      REBOOT=1
    fi

    if ! grubby --info=0 | egrep -qw "transparent_hugepage=never"
    then
      grubby --update-kernel=ALL --args="transparent_hugepage=never"
      REBOOT=1
    fi

    if ! getenforce | egrep -qw "Disabled"
    then
      sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
      setenforce 0
      REBOOT=1
    fi

    if [[ $REBOOT -eq 1 ]]
    then
      shutdown -r now
    fi

runcmd:
  - |
    set -x
    export HOME=/root

    awk 'BEGIN {OFMT = "%.0f";} /MemTotal/ {print "vm.min_free_kbytes =", $2 * .03;}' /proc/meminfo >> /etc/sysctl.d/20-gpdb.conf
    echo kernel.shmall = $(expr $(getconf _PHYS_PAGES) / 2) >> /etc/sysctl.d/20-gpdb.conf
    echo kernel.shmmax = $(expr $(getconf _PHYS_PAGES) / 2 \* $(getconf PAGE_SIZE)) >> /etc/sysctl.d/20-gpdb.conf

    sysctl -p

    systemctl stop firewalld.service
    systemctl disable firewalld.service

    mkdir -p /gpdata
    mkfs.xfs /dev/sdb
    mount -t xfs -o rw,noatime,nodev,inode64 /dev/sdb /gpdata/
    df -kh
    echo "/dev/sdb /gpdata/ xfs rw,nodev,noatime,inode64 0 0" >> /etc/fstab
    mkdir -p /gpdata/coordinator
    mkdir -p /gpdata/primary
    /sbin/blockdev --setra 16384 /dev/sdb
    echo "/sbin/blockdev --setra 16384 /dev/sdb" >> /etc/rc.d/rc.local
    chown -R gpadmin:gpadmin /gpdata

    echo "RemoveIPC=no" >> /etc/systemd/logind.conf
    service systemd-logind restart

    printf "MaxStartups 200\nMaxSessions 200\n" >> /etc/ssh/sshd_config
    service sshd restart

    /root/update-etc-hosts.sh ${internal_cidr} ${seg_count} ${offset} ${etl_bar_cdw_ip}

    echo cdw > /home/gpadmin/hosts-all
    > /home/gpadmin/hosts-segments
    for i in {1..${seg_count}}; do
      echo "sdw$${i}" >> /home/gpadmin/hosts-all
      echo "sdw$${i}" >> /home/gpadmin/hosts-segments
    done
    chown gpadmin:gpadmin /home/gpadmin/hosts*

    mkdir -p /var/log/gpv
    chmod a+rwx /var/log/gpv