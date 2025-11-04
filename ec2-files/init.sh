#!/bin/bash

set -euo pipefail

HostName=$1
Suffix=$2
Environment=$3
BucketName=$4
CertBotEmail=$5

echo "Begin init.sh"

echo "export HostName=$HostName"
echo "export Suffix=$Suffix"
echo "export Environment=$Environment"
echo "export BucketName=$BucketName"
echo "export CertBotEmail=$CertBotEmail"

# run some tests
aws sts get-caller-identity
aws s3 ls "${BucketName}"

echo "Making directories..."
# mount s3 drive
sudo -u ubuntu mkdir -p /home/ubuntu/s3bucket 
sudo -u ubuntu mkdir -p /home/ubuntu/incomplete-dir
echo "Mount S3"
sudo -u ubuntu s3fs "${BucketName}" /home/ubuntu/s3bucket -o nonempty,iam_role="${Environment}-cfn-ec2"
sleep 5

sudo -u ubuntu mkdir -p /home/ubuntu/s3bucket/Downloads
sudo -u ubuntu ln -s /home/ubuntu/s3bucket/Downloads /home/ubuntu/Downloads

# setup transmission as ubuntu user
# a tad convoluted
echo "Running: systemctl stop transmission-daemon"
systemctl stop transmission-daemon.service
sleep 5

echo "Running: systemctl disable transmission-daemon"
systemctl disable transmission-daemon.service

echo "Sleeping..."
sleep 5

echo "create the local configs by starting transmission-daemon"
sudo -u ubuntu transmission-daemon

echo "kill again so config edits last"
pid=$(ps aux | grep -v grep | grep transmission-daemon | awk '{print $2}')
if [[ -n "$pid" ]]; then
  kill -9 "$pid"
fi

echo "Running update-settings.py"
sudo -u ubuntu /var/tmp/update-settings.py

echo "start transmission again"
sudo -u ubuntu transmission-daemon -g /home/ubuntu/.config/transmission-daemon/

echo "list torrents... expecting none"
sudo -u ubuntu transmission-remote -l

# lets just sleep a bit to give DNS a chance
echo "While loop..."
threshold=0
while sleep 5; do
    if [ $threshold -gt 35 ]; then
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

echo "Un-tarring..."
tar zxf /var/tmp/letsencrypt.tgz -C /etc

CERT_PATH="/etc/letsencrypt/live/$HostName/fullchain.pem"
ls -l "$CERT_PATH"

if [ ! -f "$CERT_PATH" ] || ! openssl x509 -checkend 172800 -noout -in "$CERT_PATH"; then
  echo "Certificate is expired or not present — requesting new certificate"

  # Install Certbot if not already installed
  if ! command -v certbot >/dev/null; then
    echo "Installing certbot via snap"
    snap install core && snap refresh core
    snap install certbot --classic
  else
    echo "Certbot already installed; refreshing"
    snap refresh certbot
  fi

  # Request certificate
  certbot certonly --nginx --agree-tos -m "$CertBotEmail" -d "$HostName" -n

  # save new certs
  cd /etc
  tar zcf /tmp/letsencrypt.tgz letsencrypt
  aws s3 cp /tmp/letsencrypt.tgz s3://"${BucketName}"/letsencrypt.tgz

else
  echo "Certificate is still valid."
fi

# Replace placeholder in nginx conf and reload Nginx
echo "Generating nginx config for $HostName"
sed "s/_HOSTNAME_/${HostName}/g" /var/tmp/nginx-proxy.conf > /etc/nginx/conf.d/nginx-proxy.conf

# Validate and reload Nginx
echo "Testing nginx config"
nginx -t

echo "Reloading nginx"
nginx -s reload

sleep 1
aws s3 cp /tmp/setup.log s3://"${BucketName}"/setup.log
