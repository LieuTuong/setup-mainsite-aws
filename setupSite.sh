#!/bin/sh
#config dua tren lab cua tuonglcc
#hay sua lai ssh trong cac ham neu can thiet

#database user file
DBFILE=./database_user.txt

NGINX_AVAILABLE_VHOSTS='/usr/local/nginx/sites-available'
NGINX_ENABLE_VHOSTS='/usr/local/nginx/sites-enabled'

APACHE_AVAILABLE_VHOSTS='/efs/webapps/conf/apache2-group/conf/sites-available'
APACHE_ENABLE_VHOSTS='/efs/webapps/conf/apache2-group/conf/sites-enabled'



# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

function printError(){
	echo -e "${RED}$1${PLAIN}"
}

function Print(){
	echo -en "${GREEN}$1${PLAIN}"
}

function PrintProcess(){
	echo -en "${YELLOW}$1${PLAIN}"
}

# check root
#[[ $EUID -ne 0 ]] && echo -e "${RED}Error:${PLAIN} This script must be run as root!" && return


# doc config vhost va db
source ./configure.txt 
if [ -z $domainCode ];then
	echo "ERROR: Please input domain code to file ./config/configure.txt"
	return 
fi

devDomain="dev.${domainCode}"
realDomain="${domainCode}"
devDB="${gameCode}dev_data"
devDBUser="${gameCode}dev_dt"
realDB="${gameCode}_data"
realDBUser="${gameCode}_dt"


function dev_vhost_for_nginx(){
	PrintProcess "Setup on DEV Nginx Cportal Server...........\n"
	ssh -i ~/.ssh/id_rsa $ipVportal bash -c "'
	sudo mkdir -p /var/log/nginx/$devDomain
	sudo cp $NGINX_AVAILABLE_VHOSTS/dev.original.conf $NGINX_AVAILABLE_VHOSTS/$devDomain.conf
	sudo sed -i 's/original/${devDomain}/g' $NGINX_AVAILABLE_VHOSTS/$devDomain.conf
	sudo ln -s $NGINX_AVAILABLE_VHOSTS/$devDomain.conf $NGINX_ENABLE_VHOSTS/$devDomain.conf
'"
}



function real_vhost_for_nginx(){
	PrintProcess "Setup on REAL Nginx Cportal Server...........\n"
	ssh -i ~/.ssh/id_rsa $ipVportal bash -c "'
	sudo mkdir -p /var/log/nginx/$realDomain
	sudo cp $NGINX_AVAILABLE_VHOSTS/original.conf $NGINX_AVAILABLE_VHOSTS/$realDomain.conf
	sudo sed -i 's/original/${realDomain}/g' $NGINX_AVAILABLE_VHOSTS/$realDomain.conf
	sudo ln -s $NGINX_AVAILABLE_VHOSTS/$realDomain.conf $NGINX_ENABLE_VHOSTS/$realDomain.conf
'"
}


function restart_nginx(){
	ssh -i ~/.ssh/id_rsa $ipVportal "sudo -i nginx -t"
	if [ $? -ne 0 ];then
		printError "nginx -t failed, please check config again!!!"
		return 
	fi

	ssh -i ~/.ssh/id_rsa $ipVportal "sudo systemctl restart nginx"
	if [ $? -eq 0 ];then
		Print "configure NGINX server success!!!!!!!!!!!!!!!\n"
	else
		printError "Restart nginx on cportal failed, please check again!!!"
		return 
	fi
	echo -e "\n-------------------------------------------"
}

function vhost_apache(){
	PrintProcess "Setup vhost on APACHE Server......."

	ssh -i ~/.ssh/id_rsa $ipVportal bash -c "'
	sudo cp $APACHE_AVAILABLE_VHOSTS/original.conf $APACHE_AVAILABLE_VHOSTS/$realDomain.conf
	sudo sed -i 's/original/${realDomain}/g' $APACHE_AVAILABLE_VHOSTS/$realDomain.conf
	sudo ln -s $APACHE_AVAILABLE_VHOSTS/$realDomain.conf $APACHE_ENABLE_VHOSTS/$realDomain.conf
	'"

	ssh -i ~/tuonglcc-aws.pem $ipFE "httpd -t" 
	if [ $? -ne 0 ];then
		printError "Check apache config server, please check again!!!"
		return
	fi

	ssh -i ~/.ssh/id_rsa $ipVportal 'sudo su -c "echo 1 > /efs/webapps/signal/apache"'  #reload apache
	Print "configure APACHE server success!!!!!!!!!!!!!!!\n"
	echo "-------------------------------------------"

}

	
function setupDB(){
	
	ssh -i ~/.ssh/id_rsa $ipDB <<EOF

	mysql -e "CREATE DATABASE ${devDB};"
	if [ $? -ne 0 ] ;exit ; fi
	mysql -e "CREATE USER ${devDBUser}@'%' IDENTIFIED BY '${pwdDBDev}';"
	mysql -e "GRANT ALL PRIVILEGES ON ${devDB}.* TO ${devDBUser}@'%';"

	
	mysql -e "CREATE DATABASE ${realDB};"
	if [ $? -ne 0 ]; exit; fi
	mysql -e "CREATE USER ${realDBUser}@'%' IDENTIFIED BY '${pwdDBReal}';"
	mysql -e "GRANT ALL PRIVILEGES ON ${realDB}.* TO ${realDBUser}@'%';"

	mysql -e "FLUSH PRIVILEGES;"
EOF
	Print "configure MySQL DB success!!!!!!!!!!!!!!!\n"
	echo "-------------------------------------------"
}



## ======== MAIN =========




Print "Set up vhost on VPortal Nginx (yes/no): "
read check_vportal_nginx
while [ $check_vportal_nginx != "yes" ] && [ $check_vportal_nginx != "no" ];
do
  printError "@@ Please confirm to yes or no to continue"
  Print "Set up vhost on VPortal Nginx (yes/no): " 
  read check_vportal_nginx
done

if [ $check_vportal_nginx = "yes" ];then
	Print "\tChoose: \n"
	Print "\t1. domain for dev: dev.xxx.yyy.zzz\n\t2. domain for real: xxx.yyy.zzz\n\t3. both\n"
	read nginx_opt
	while [ $nginx_opt != "1" ] && [ $nginx_opt != "2" ] && [ $nginx_opt != "3" ];
	do
  		printError "@@ Please choose [1-3] to continue: " 
  		read nginx_opt
	done
fi

Print "Set up vhost on FE Apache (yes/no):"
read check_fe_apache
while [ $check_fe_apache != "yes" ] && [ $check_fe_apache != "no" ];
do
  printError "@@ Please confirm to yes or no to continue"
  Print "Set up vhost on FE Apache (yes/no): " 
  read check_fe_apache
done

Print "Set up Database (yes/no): "
read check_db
while [ $check_db != "yes" ] && [ $check_db != "no" ];
do
  printError "@@ Please confirm to yes or no to continue"
  Print "Set up Database (yes/no): "
  read check_db
done

echo -e "### Site will be configure is: "
echo -e "- Domain: $realDomain"
if [ $check_db = "yes" ];then
	echo -e "- Database development: DBName: $devDB | DBUser: $devDBUser | PWD: $pwDBDev" | tee -a $DBFILE
	echo -e "- Database production: DBName: $realDB | DBUser: $realDBUser | PWD: $pwDBReal" | tee -a $DBFILE
fi


Print "Please confirm yes to continue: "
read check 
if [ -z $check ] || [ $check != "yes" ];then
	PrintProcess "Terminate"
	return
fi

# nginx vhost
if [ $check_vportal_nginx = "yes" ];then
	if [ $nginx_opt = "1" ];then
		dev_vhost_for_nginx
	elif [ $nginx_opt = "2" ];then
		real_vhost_for_nginx
	else 
		dev_vhost_for_nginx
		real_vhost_for_nginx
	fi	

	restart_nginx
fi

# apache FE
if [ $check_fe_apache = "yes" ];then
	vhost_apache
fi

# DB
if [ $check_db = "yes" ];then
	setupDB
fi


