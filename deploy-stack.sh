#!/usr/bin/env bash

region="eu-west-1"
stack_name="hg-ec2"
stack_file="cfn/ec2.yml"
parameters_file="cfn/ec2-parameters.json"

hostname=$(jq -r '.[] | select(.ParameterKey == "HostName") | .ParameterValue' ${parameters_file})
s3bucket=$(jq -r '.[] | select(.ParameterKey == "BucketName") | .ParameterValue' ${parameters_file})

aws s3 cp ./upload-files/nginx-proxy.conf s3://${s3bucket}/nginx-proxy.conf
aws s3 cp ./upload-files/init.sh s3://${s3bucket}/init.sh
aws s3 cp ./upload-files/update-settings.py s3://${s3bucket}/update-settings.py

aws cloudformation --region "${region}" create-stack \
    --stack-name "${stack_name}" \
    --template-body "file://${stack_file}" \
    --parameters "file://${parameters_file}" \
    --capabilities CAPABILITY_NAMED_IAM

if [[ $? != 0 ]]; then
    echo "Something went wrong with create-stack. Here are the exports."
    aws cloudformation list-exports \
        --query 'Exports[*].[Name,Value]' \
        --output table
    echo -e "\n\nExiting..."
    exit 1
fi

# loop until completion
while true; do
    created=$(aws --region=${region} cloudformation \
        --output json list-stacks --stack-status-filter CREATE_COMPLETE |
        jq -r --arg STACK_NAME "${stack_name}" '.StackSummaries[] | select((.StackName==$STACK_NAME))'
    );
    if [ -n "${created}" ]; then
        sleep 10
        echo "[Creation of '${stack_name}' completed]"
        break
    fi
    echo -ne "."
    sleep 5
done

myip=$(curl -s https://ipinfo.io/ip ; echo) || { echo "Could not get your IP"; exit 1; }

secgrp=$(aws cloudformation list-exports \
    --query "Exports[?Name=='prod-cfn-ec2-download-secgrp'].Value" \
    --output text)

echo "My IP: ${myip}"
echo "SecGrp: ${secgrp}"

# open ssh to my IP
aws --region "${region}" ec2 authorize-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp \
    --port 22 \
    --cidr "${myip}/32"

# open nginx port 443 to my IP
aws --region "${region}" ec2 authorize-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp \
    --port 443 \
    --cidr "${myip}/32"

aws cloudformation list-exports \
    --query 'Exports[*].[Name,Value]' \
    --output table

# wait until dns entry is created. for now, there is no timeout
while sleep 1; do
    if nc -w 2 -z ${hostname} 443 2>/dev/null; then
        echo "\n $(nc -w 2 -vz ${hostname} 443)"
        break
    else
        echo -n "."
    fi
done

echo -ne "Revoke port 80... in sec group ${secgrp}"
aws --region "${region}" ec2 revoke-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "S3 bucket = $s3bucket"
