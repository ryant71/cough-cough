#!/usr/bin/env bash

if [[ -z "$1" ]]
then
	echo "Usage: $0 <port>"
	exit 1
else
	port=$1
fi

secgrp=$(aws cloudformation list-exports \
	--query "Exports[?Name=='prod-cfn-ec2-download-secgrp'].Value" \
	--output text)

[[ -z "$secgrp" ]] && { echo "Security Group not found"; exit 1; }
echo "Security Group: ${secgrp}"

# open nginx port $port to my IP
aws ec2 authorize-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp \
    --port $port \
    --cidr 0.0.0.0/0


