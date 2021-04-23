#version=RHEL8
ignoredisk --only-use=sda
# Partition clearing information
clearpart --all --initlabel --drives=sda
# Use text install
text
# Network information
network --activate --bootproto=dhcp --device=link --onboot=on --ipv6=auto
network --hostname=<system>.localdomain
# Install via http
url --url="http://192.168.86.105/ks/tree/BaseOS/x86_64/os"
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

#Root password
rootpw --lock
# Run the Setup Agent on first boot
#firstboot --enable
# Do not configure the X Window System
skipx
# Ensure SELinux enforcing
selinux --enforcing
# System services
services --enabled="chronyd"
# System timezone
timezone America/New_York --isUtc
user --groups=wheel --name=bootstrap --password=<redacted> --iscrypted --gecos="Bootstrap User"
sshkey --username bootstrap "ssh-rsa <redacted>"
# Disk partitioning information
part /boot --fstype="ext4" --ondisk=sda --size=7168
part pv.345 --fstype="lvmpv" --ondisk=sda --size=25600
part /cluster-storage --fstype="xfs" --ondisk=sda --size=1024 --grow
part /boot/efi --fstype="efi" --ondisk=sda --size=600 --fsoptions="umask=0077,shortname=winnt"
volgroup cl --pesize=4096 pv.345
logvol / --fstype="xfs" --grow --size=1024 --name=root --vgname=cl

%packages
@^server-product-environment
@hardware-monitoring
@headless-management
kexec-tools

%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end

%post
systemctl enable cockpit.socket
echo -e "bootstrap\tALL=(ALL)\tNOPASSWD: ALL" > /etc/sudoers.d/bootstrap
%end

reboot
