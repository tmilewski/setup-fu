#!/bin/bash

shopt -s nocaseglob
set -e

user="deploy"
group="wheel"
locale="en_US.UTF-8"
setupfu_path=$(cd && pwd)/setup-fu
local_path="/home/$user/setup-fu"
log_file="$setupfu_path/install.log"
repository="https://github.com/tmilewski/setup-fu/raw/master"
templates_location="$repository/templates"

control_c()
{
  echo -en "\n\n*** Exiting ***\n\n"
  exit 1
}

# trap keyboard interrupt (control-c)
trap control_c SIGINT

echo -e "\n\n"
echo "#################################"
echo "############# SETUP #############"
echo "#################################"

echo -e "\n\n"
echo "Log File: $log_file"

## PROMPT FOR PUBLIC KEY
echo -e "\n"
echo "Please enter your public key: "
read public_key

## PROMPT FOR SSH PORT
echo -e "\n"
echo "Please enter a port for SSH: "
read ssh_port

## CREATE INSTALL DIR
echo -e "\n=> Creating install dir..."
cd && mkdir -p $setupfu_path/src && cd $setupfu_path && touch $setupfu_path/install.log
echo "==> done..."

## ADD NEW GROUP
echo -e "\n=> Adding $group group..."
#passwd
/usr/sbin/groupadd $group
echo "%$group  ALL=(ALL)       ALL" >> "/etc/sudoers"
set rebinddelete
echo "==> done..."

## ADD NEW USER
echo -e "\n=> Adding $user user..."
/usr/sbin/adduser $user
/usr/sbin/usermod -a -G $group $user
echo "==> done..."

## SSH KEYS
echo -e "\n=> Installing SSH keys..."
mkdir /home/$user/.ssh
touch /home/$user/.ssh/authorized_keys
echo "$public_key" >> "/home/$user/.ssh/authorized_keys"
chown -R $user:$user /home/$user/.ssh
chmod 700 /home/$user/.ssh
chmod 600 /home/$user/.ssh/authorized_keys
echo "==> done..."

## CONFIGURE SSHD
echo -e "\n=> Configuring sshd..."
wget --no-check-certificate -O /etc/ssh/sshd_config $templates_location/sshd/sshd_config
sed -i -e "s/^Port .*$/Port $ssh_port/" \
			 -e "s/^AllowUsers: .*$/AllowUsers $user/" \
			/etc/ssh/sshd_config
echo "==> done..."

## CONFIGURE IPTABLES
echo -e "\n=> Configuring iptables..."
/sbin/iptables -F
wget --no-check-certificate -O /etc/iptables.up.rules $templates_location/iptables/iptables.up.rules
sed -i "s/-A INPUT -p tcp -m state --state NEW --dport 30000 -j ACCEPT$/-A INPUT -p tcp -m state --state NEW --dport $ssh_port -j ACCEPT/" /etc/iptables.up.rules
/sbin/iptables-restore < /etc/iptables.up.rules
wget --no-check-certificate -O /etc/network/if-pre-up.d/iptables $templates_location/iptables/iptables
chmod +x /etc/network/if-pre-up.d/iptables
/etc/init.d/ssh reload
echo "==> done..."

## CONFIGURE LOCALE
echo "\n=> Configuring locale..."
sudo /usr/sbin/locale-gen $locale
sudo /usr/sbin/update-locale LANG=$locale
echo "==> done..."

## CREATE LOCAL INSTALL DIR
echo -e "\n=> Creating local install dir..."
cd && mkdir -p $local_path/src && cd $local_path && touch $setupfu_path/install.log
echo "==> done..."

## RUN THE REST OF THE SETUP AS A NORMAL USER
echo -e "\n=> Running the rest of the setup as $user\n"
wget --no-check-certificate -O $local_path/src/installer.sh $repository/installer.sh && cd $local_path/src && su - $user -c "bash installer.sh $log_file"