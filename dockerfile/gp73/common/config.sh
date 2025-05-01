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