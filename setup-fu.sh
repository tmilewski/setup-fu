#!/bin/bash

shopt -s nocaseglob
set -e

distro="ubuntu"
user="deploy"
group="wheel"
locale="en_US.UTF-8"
ruby_version="1.9.2"
ruby_version_string="1.9.2p180"
script_runner=$(whoami)
setupfu_path=$(cd && pwd)/setup-fu
log_file="$setupfu_path/install.log"
templates_location="https://github.com/tmilewski/setup-fu/raw/master/templates/"

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

## PROMPT FOR DATABASE INSTALL
echo -e "\n"
echo "What database would you like to install?"
echo "=> 1. MySQL"
echo "=> 2. MongoDB (not implemented yet)"
echo "=> 3. Postgres (not implemented yet)"
echo "=> 4. None"
echo -n "Select your database [1/2/3/4]? "
read install_database

# PROMPT FOR POSTFIX INSTALL
echo -e "\n"
echo "Install Postfix [Y/N]? (Not fully implemented, hit N)"
read install_postfix

## PROMPT FOR PUBLIC KEY
echo -e "\n"
echo "Please enter your public key: "
read public_key

## PROMPT FOR SSH PORT
echo -e "\n"
echo "Please enter a port for SSH: "
read ssh_port

## ADD NEW GROUP
echo "\n=> Adding $group group..."
#passwd
/usr/sbin/groupadd $group
echo "%$group  ALL=(ALL)       ALL" >> "/usr/sbin/visudo"
#set rebinddelete
echo "==> done..."

## ADD NEW USER
echo "\n=> Adding $user user..."
/usr/sbin/adduser $user
/usr/sbin/usermod -a -G $group $user
echo "==> done..."

## SSH KEYS
echo "\n=> Installing SSH keys..."
mkdir /home/$user/.ssh
touch /home/$user/.ssh/authorized_keys
echo "$public_key" >> "/home/$user/.ssh/authorized_keys"
chown -R $user:$user /home/$user/.ssh
chmod 700 /home/$user/.ssh
chmod 600 /home/$user/.ssh/authorized_keys
echo "==> done..."

## CONFIGURE SSHD
echo "\n=> Configuring sshd..."
wget --no-check-certificate -O /etc/ssh/sshd_config $templates_location/sshd/sshd_config
sed -e "s/^Port .*$/Port: $ssh_port/" \
		-e "s/^AllowUsers: .*$/AllowUsers: $user/" \
		/etc/ssh/sshd_config
echo "==> done..."

## CONFIGURE IPTABLES
echo "\n=> Configuring iptables..."
/sbin/iptables -F
wget --no-check-certificate -O /etc/iptables.up.rules $templates_location/iptables/iptables.up.rules
sed "s/-A INPUT -p tcp -m state --state NEW --dport 30000 -j ACCEPT$/-A INPUT -p tcp -m state --state NEW --dport $ssh_port -j ACCEPT/" /etc/iptables.up.rules
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

## CHECK AND DISALLOW IF USER IS ROOT
if [ $script_runner == "root" ] ; then
  echo -e "\nThis script must be run as a normal user with sudo privileges\n"
  exit 1
fi

# CHECK IF USER HAS SUDO PRIVILEGES
sudo -v >/dev/null 2>&1 || { echo $script_runner has no sudo privileges ; exit 1; }

echo -e "\n\n!!! Set to install RVM for user: $script_runner !!! \n"

## CREATE INSTALL DIR
echo -e "\n=> Creating install dir..."
cd && mkdir -p setup-fu/src && cd setup-fu && touch install.log
echo "==> done..."


## ENSURE .BASHRC AND .BASH_PROFILE EXIST
echo -e "\n=> Ensuring there is a .bashrc and .bash_profile..."
touch $HOME/.bashrc && touch $HOME/.bash_profile
echo "==> done..."


## ESURE THAT APTITUDE EXISTS AND, IF POSSIBLE, DEFAULT TO THAT
echo -e "\n=> Ensuring that aptitude exists and default to that, if possible..."
if command -v aptitude >/dev/null 2>&1 ; then
  pm="aptitude"
else
  pm="apt-get"
fi
echo -e "\nUsing $pm for package installation\n"


## UPDATE THE SYSTEM
echo -e "\n=> Updating system (this may take awhile)..."
sudo $pm update >> $log_file 2>&1 \
		&& sudo $pm -y upgrade >> $log_file 2>&1
echo "==> done..."


# INSTALL BUILD TOOLS
echo -e "\n=> Installing build tools..."
sudo $pm -y install \
    wget curl build-essential \
    bison openssl zlib1g \
    libxslt1.1 libssl-dev libxslt1-dev \
    libxml2 libffi-dev libyaml-dev \
    libxslt-dev autoconf libc6-dev \
    libreadline6-dev zlib1g-dev libcurl4-openssl-dev >> $log_file 2>&1
echo "==> done..."


## INSTALL LIBS NEEDED FOR SQLITE AND MYSQL
echo -e "\n=> Installing libs needed for sqlite and mysql..."
sudo $pm -y install libsqlite3-0 sqlite3 libsqlite3-dev libmysqlclient16-dev libmysqlclient16 >> $log_file 2>&1
echo "==> done..."


## INSTALL DATABASE

if [$install_database -eq 1 ] ; then
  echo -e "\n=> Installing MySQL (you will be prompted for a password)..."
	sudo $pm -y install mysql-server mysql-client >> $log_file 2>&1
	echo "done..."
else
  echo -e "\nContinuing without installing a database..\n"
fi

## INSTALL POSTFIX
if [ $install_postfix == "Y" ] ; then
	echo -e "\n=> Install postfix..."
	sudo $pm -y install postfix >> $log_file 2>&1
	
	sed '/# Allow Postfix/ a\' \
			'-I INPUT -p tcp --dport 25 -m state --state NEW,ESTABLISHED -j ACCEPT\' \
			'-I OUTPUT -p tcp --sport 25 -m state --state NEW,ESTABLISHED -j ACCEPT'
			
	# TODO: Configuration
			
	sudo /etc/init.d/postfix start
	sudo /usr/sbin/update-rc.d postfix defaults
	echo "==> done..."
fi

# INSTALL IMAGEMAGICK
echo -e "\n=> Installing imagemagick (this may take awhile)..."
sudo $pm -y install imagemagick libmagick9-dev >> $log_file 2>&1
echo "==> done..."

# INTALL GIT
echo -e "\n=> Installing git..."
sudo $pm -y install git-core >> $log_file 2>&1
echo "==> done..."

#now that all the distro specific packages are installed lets get Ruby

## INSTALL RUBY
echo -e "\n=> Installing RVM the Ruby enVironment Manager http://rvm.beginrescueend.com/rvm/install/ \n"
curl -O -L http://rvm.beginrescueend.com/releases/rvm-install-head
chmod +x rvm-install-head
"$PWD/rvm-install-head" >> $log_file 2>&1
[[ -f rvm-install-head ]] && rm -f rvm-install-head
echo -e "\n=> Setting up RVM to load with new shells..."
#if RVM is installed as user root it goes to /usr/local/rvm/ not ~/.rvm
echo  '[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"  # Load RVM into a shell session *as a function*' >> ~/.bash_profile
echo "==> done..."
echo "=> Loading RVM..."
source ~/.rvm/scripts/rvm
source ~/.bashrc
source ~/.bash_profile
echo "==> done..."
echo -e "\n=> Installing Ruby $ruby_version_string (this will take awhile)..."
echo -e "=> More information about installing rubies can be found at http://rvm.beginrescueend.com/rubies/installing/ \n"
rvm install $ruby_version >> $log_file 2>&1
echo -e "\n==> done..."
echo -e "\n=> Using 1.9.2 and setting it as default for new shells..."
echo "=> More information about Rubies can be found at http://rvm.beginrescueend.com/rubies/default/"
rvm --default use $ruby_version >> $log_file 2>&1
echo "==> done..."


# Reload bash
echo -e "\n=> Reloading shell so ruby and rubygems are available..."
source ~/.bashrc
source ~/.bash_profile
echo "==> done..."

echo -e "\n=> Installing Bundler, Passenger and Rails.."
gem install bundler passenger rails --no-ri --no-rdoc >> $log_file 2>&1
echo "==> done..."

echo -e "\n#################################"
echo    "### Installation is complete! ###"
echo -e "#################################\n"

echo -e "\n !!! logout and back in to access Ruby or run source ~/.bash_profile !!!\n"