#!/usr/bin/env bash

if [ "$USER" = "root" ]; then
    echo 'You should not run this script as root.'; exit 1
fi

distro=$(cat /etc/os-release | awk -F= '/^ID=.*/ {print $2}')
if [ "$distro" = "ubuntu" ]; then
    url='https://ubuntu.com/tutorials/install-and-configure-wordpress#1-overview'
    xdg-open $url &
    disown
    echo "Follow the instructons at: $url"
    exit 0
fi

comment() {
    sudo sed -i "/^$1$/s/.*/$sym$1/" $file
}
uncomment() {
    sudo sed -i "/^$sym$1$/s/.*/$1/" $file
}

sudo pacman -S --noconfirm --needed yay base-devel unzip

# MariaDB/MySQL
sudo pacman -S --noconfirm --needed mysql
sudo mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
sudo systemctl enable --now mysql
sudo mysql -e "CREATE USER 'admin'@'localhost' IDENTIFIED BY 'password';"
sudo mysql -e "CREATE DATABASE wordpress;"
sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'admin'@'localhost' IDENTIFIED BY 'password';"
sudo mysql -e "FLUSH PRIVILEGES;"

# PHP
sudo pacman -S --noconfirm --needed php xdebug

file='/etc/php/conf.d/xdebug.ini'
sym=';'
uncomment 'zend_extension=xdebug'
uncomment 'xdebug.remote_enable=on'
uncomment 'xdebug.remote_host=127.0.0.1'
uncomment 'xdebug.remote_port=9000'
uncomment 'xdebug.remote_handler=dbgp'

# Fixes 'Call to undefined function mysql_connect()'
file='/etc/php/php.ini'
sym=';'
uncomment 'extension=pdo_mysql'
uncomment 'extension=mysqli'

# Apache
sudo pacman -S --noconfirm --needed apache php-apache
file='/etc/httpd/conf/httpd.conf'
sym='#'
comment 'LoadModule mpm_event_module modules\/mod_mpm_event.so'
uncomment 'LoadModule mpm_prefork_module modules\/mod_mpm_prefork.so'
uncomment 'LoadModule rewrite_module modules\/mod_rewrite.so'

sudo tee -a /etc/httpd/conf/httpd.conf << EOF
LoadModule php7_module modules/libphp7.so
AddHandler php7-script .php
Include conf/extra/php7_module.conf
EOF

sudo systemctl start httpd
sudo systemctl enable httpd

# WordPress
sudo pacman -S --noconfirm --needed wordpress phpmyadmin
yay -S --noconfirm --needed wp-cli

sudo tee /etc/httpd/conf/extra/httpd-wordpress.conf << EOF
<VirtualHost *:80>
	DocumentRoot /usr/share/webapps/wordpress
	<Directory /usr/share/webapps/wordpress>
		Options +Indexes +FollowSymLinks +ExecCGI
          	AllowOverride All
          	Order deny,allow
          	Allow from all
          	Require all granted
	</Directory>
</VirtualHost>
EOF

sudo tee -a /etc/httpd/conf/httpd.conf << EOF
Include conf/extra/httpd-wordpress.conf
EOF

sudo systemctl restart httpd
sudo systemctl enable --now mysqld

# Fixes 'Plugins are unable to install: Could not create directory'
sudo groupadd wp
sudo usermod -a -G wp http
sudo usermod -a -G wp "$USER"
sudo chown http:wp -R /usr/share/webapps/wordpress
sudo chmod -R 774 /usr/share/webapps/wordpress 

pushd /usr/share/webapps/wordpress

# Fixes 'Cannot save plugins to localhost'
file='/usr/share/webapps/wordpress/wp-config.php'
if [ -f $file ]; then
    sudo sed -ri "/^(\s*|#*\s*|/{2,}\s*)?define\('FS_METHOD'.*/s/.*/define('FS_METHOD', 'direct');/" $file
else
    wp config create --dbname='wordpress' --dbuser='admin' --dbpass='password' --skip-check
    sudo tee -a $file << EOF
define('FS_METHOD', 'direct');
EOF
fi

wp core install --url=localhost --title='WordPress' --admin_user='admin' --admin_password='password' --admin_email='youremail@example.com' --skip-email
popd

xdg-open 'http://localhost' >/dev/null 2>&1 &
disown
