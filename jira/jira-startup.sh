yum install -y wget
yum install -y jq
yum install -y unzip

mv /etc/localtime /etc/localtime.bak
ln -s /usr/share/zoneinfo/Canada/Eastern /etc/localtime
