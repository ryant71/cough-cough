#!/usr/bin/env bash

REGION="eu-west-1"

function list_stacks(){
  aws cloudformation list-stacks \
    --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].[StackName,StackStatus,CreationTime,LastUpdatedTime]" \
    --output table
}

function list_ec2(){
  aws ec2 describe-instances \
    --query "Reservations[*].Instances[0].[KeyName,PrivateIpAddress,LaunchTime,State.Name]" \
    --output table
}

function delete_stack(){
  local stack_name="$1"

  echo "Deleting Stack: $stack_name"
  aws cloudformation \
      --region "${REGION}" delete-stack \
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
      inprogess=$(aws --region=${REGION} cloudformation \
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
  [[ "$stack_name" == "hg-ec2" ]] && list_ec2
}

usage() {
  echo "Usage:"
  echo "  $0 --list-ec2"
  echo "  $0 --list-stacks"
  echo "  $0 --delete stack1 [stack2 ...]"
  echo "  $0 [--help]"
}

[[ "$#" == 0 ]] && { usage; exit 0; }

DELETE_LIST=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list-ec2)
      list_ec2
      exit 0
      ;;
    --list-stacks)
      list_stacks
      exit 0
      ;;
    --delete)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        DELETE_LIST+=("$1")
        shift
      done
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Enforce some deletion order
if [[ " ${DELETE_LIST[*]} " =~ " hg-ec2 " ]]; then
  delete_stack "hg-ec2"
fi
if [[ " ${DELETE_LIST[*]} " =~ " hg-vpc " ]]; then
  delete_stack "hg-vpc"
fi
