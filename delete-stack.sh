#!/usr/bin/env bash

region="eu-west-1"
stack_name="hg-ec2"

aws cloudformation --region "${region}" delete-stack \
    --stack-name "${stack_name}"

if [[ $? != 0 ]]; then
    echo "Something went wrong with delete-stack. Here are the exports."
    aws cloudformation list-exports \
        --query 'Exports[*].[Name,Value]' \
        --output table
    echo -e "\n\nExiting..."
    exit 1
fi

# loop until completion
while true; do
    inprogess=$(aws --region=${region} cloudformation \
        --output json list-stacks --stack-status-filter DELETE_IN_PROGRESS |
        jq -r --arg STACK_NAME "${stack_name}" '.StackSummaries[] | select((.StackName==$STACK_NAME))'
    );
    if [ -n "${inprogess}" ]; then
        echo -ne "."
        sleep 5
    else
        echo "[Deletion of '${stack_name}' completed]"
        break
    fi
done
