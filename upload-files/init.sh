#!/bin/bash

set -xe

HostName=$1
Suffix=$2
Environment=$3
BucketName=$4
CertBotEmail=$5

echo "export HostName=$HostName"
echo "export Suffix=$Suffix"
echo "export Environment=$Environment"
echo "export BucketName=$BucketName"
echo "export CertBotEmail=$CertBotEmail"

# run some tests
aws sts get-caller-identity
aws s3 ls "${BucketName}"

# mount s3 drive
sudo -u ubuntu mkdir -p /home/ubuntu/s3bucket
sudo -u ubuntu s3fs "${BucketName}" /home/ubuntu/s3bucket -o nonempty,iam_role="${Environment}-cfn-ec2"
sudo -u ubuntu mkdir -p /home/ubuntu/s3bucket/Downloads
sudo -u ubuntu mkdir -p /home/ubuntu/incomplete-dir
sudo -u ubuntu ln -s /home/ubuntu/s3bucket/Downloads /home/ubuntu/Downloads

# setup transmission as ubuntu user
# a tad convoluted
echo "systemctl stop transmission-daemon"
systemctl stop transmission-daemon
sleep 3
echo "kill transmission-daemon just in case"
pid="$(ps aux | grep transmission-daemon | grep -v grep | awk '{print $2}')"
[[ -n "$pid" ]] && kill $pid

echo "create the local configs"
sudo -u ubuntu transmission-daemon
echo "kill again so config edits last"
pid="$(ps aux | grep transmission-daemon | grep -v grep | awk '{print $2}')"
[[ -n "$pid" ]] && kill $pid
sleep 1

sudo -u ubuntu /tmp/update-settings.py

echo "start again"
sudo -u ubuntu transmission-daemon -g /home/ubuntu/.config/transmission-daemon/

# lets just sleep a bit to give DNS a chance
threshold=0
while sleep 5; do
    if [ $threshold -gt 25 ]; then
        echo "This is taking too long"
        break
    fi
    myhost=$(dig @8.8.8.8 +short -4 "${HostName}")
    if [ -z "${myhost}" ]
    then
        echo -n ".${myhost}"
    else
        echo "ip=${myhost}, now doing certbot"
        break
    fi
    threshold=$((threshold + 1))
done

# certbot is run and edits the default nginx config
echo "Install certbot"
snap refresh
snap install certbot --classic

echo "certbot certonly --nginx --agree-tos -m ${CertBotEmail} -d ${HostName} -n"
certbot certonly --nginx --agree-tos -m "${CertBotEmail}" -d "${HostName}" -n 2>&1

echo "Running sed on nginx-proxy.conf"
sed "s/_HOSTNAME_/${HostName}/g" /tmp/nginx-proxy.conf > /etc/nginx/conf.d/nginx-proxy.conf

nginx -t 2>&1
nginx -s reload 2>&1

exit 0
