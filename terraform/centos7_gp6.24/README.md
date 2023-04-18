# Prepare centos7 template

## Install cloud-init from source

```
git clone https://github.com/cloud-init/cloud-init.git
cd cloud-init
sudo pip3 install -r requirements.txt 
sudo python3 setup.py build
sudo python3 setup.py install --init-system systemd
sudo cloud-init init --local
sudo cloud-init status

sudo ln -s /usr/local/bin/cloud-init /usr/bin/cloud-init
for svc in cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service; do
  sudo systemctl enable $svc
  sudo systemctl start  $svc
done
```

## Update /etc/cloud/cloud.cfg

```

# The top level settings are used as module
# and base configuration.
# A set of users which may be applied and/or used by various modules
# when a 'default' entry is found it will reference the 'default_user'
# from the distro configuration specified below
users:
   - default


# If this is set, 'root' will not be able to ssh in and they
# will get a message to login instead as the default $user
disable_root: false

mount_default_fields: [~, ~, 'auto', 'defaults,nofail,x-systemd.requires=cloud-init.service,_netdev', '0', '2']
resize_rootfs_tmp: /dev
ssh_pwauth:   true

# This will cause the set+update hostname module to not operate (if true)
preserve_hostname: false

# If you use datasource_list array, keep array items in a single line.
# If you use multi line array, ds-identify script won't read array items.
# Example datasource config
# datasource:
#    Ec2:
#      metadata_urls: [ 'blah.com' ]
#      timeout: 5 # (defaults to 50 seconds)
#      max_wait: 10 # (defaults to 120 seconds)
datasource:
  OVF:
    allow_raw_data: false
datasource_list:
- OVF
- VMware

# Default redhat settings:
ssh_deletekeys:   true
ssh_genkeytypes:  ['rsa', 'ecdsa', 'ed25519']
syslog_fix_perms: ~
disable_vmware_customization: true
manage_etc_hosts: false
prefer_fqdn_over_hostname: "false"

# The modules that run in the 'init' stage
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca-certs
 - rsyslog
 - users-groups
 - ssh

# The modules that run in the 'config' stage
cloud_config_modules:
 - ssh-import-id
 - locale
 - set-passwords
 - rh_subscription
 - spacewalk
 - yum-add-repo
 - ntp
 - timezone
 - disable-ec2-metadata
 - runcmd

# The modules that run in the 'final' stage
cloud_final_modules:
 - package-update-upgrade-install
 - write-files-deferred
 - puppet
 - chef
 - ansible
 - mcollective
 - salt-minion
 - reset_rmc
 - refresh_rmc_and_interface
 - rightscale_userdata
 - scripts-vendor
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - install-hotplug
 - phone-home
 - final-message
 - power-state-change

# System and/or distro specific settings
# (not accessible to handlers/transforms)
system_info:
   # This will affect which distro class gets used
   distro: centos
   # Default user name + that default users groups (if added/used)
   default_user:
     name: cloud-user
     lock_passwd: true
     gecos: Cloud User
     groups: [adm, systemd-journal]
     sudo: ["ALL=(ALL) NOPASSWD:ALL"]
     shell: /bin/bash
   # Other config here will be given to the distro class and/or path classes
   paths:
      cloud_dir: /var/lib/cloud/
      templates_dir: /etc/cloud/templates/
   ssh_svcname: sshd
   network:
      renderers: ['netplan', 'network-manager', 'networkd', 'sysconfig', 'eni']
```

# Apply terraform
```
terraform plan -var-file=gp.tfvars
terraform apply -var-file=gp.tfvars
```

