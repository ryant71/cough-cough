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

exit_code=$?

if [[ $exit_code != 0 ]]; then
    echo "Something went wrong with create-stack."
    echo -e "\n\nExiting..."
    exit $exit_code
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

# get exports
stack_outputs=$(aws cloudformation describe-stacks --stack-name "$stack_name" --output json)

# get security group id from exports json
secgrp=$(echo $stack_outputs | jq -r '.Stacks[0].Outputs[] | select(.ExportName == "prod-cfn-ec2-download-secgrp") | .OutputValue')

# get my IP address so I can open ssh and https
myip=$(curl -s https://ipinfo.io/ip ; echo) || { echo "Could not get your IP"; exit 1; }

echo "My IP: ${myip}"

# print all exports
echo "$stack_outputs" | jq -r '.Stacks[].Outputs[] | [.ExportName, .OutputValue] | @tsv' | column -t -N Name,Value

# open ssh to my IP
aws --region "${region}" ec2 authorize-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp \
    --port 22 \
    --cidr "${myip}/32" >/dev/null

# open nginx port 443 to my IP
aws --region "${region}" ec2 authorize-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp \
    --port 443 \
    --cidr "${myip}/32" >/dev/null


# wait until EC2 dns entry is created. for now, there is no timeout
echo "Waiting for EC2 DNS to propagate"
while sleep 1; do
    if nc -w 2 -z ${hostname} 443 2>/dev/null; then
        echo "\n $(nc -w 2 -vz ${hostname} 443)"
        break
    else
        echo -n "."
    fi
done

# HTTP is no longer needed
echo -ne "Revoke port 80... in sec group ${secgrp}"
aws --region "${region}" ec2 revoke-security-group-ingress \
    --group-id "${secgrp}" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
