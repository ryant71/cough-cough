#!/usr/bin/env bash

set -euo pipefail

# Config
region="eu-west-1"
LOG_FILE="/tmp/deploy-$(date +%Y%m%d-%H%M%S).log"
VERBOSE=false  # Override with --verbose flag
ONLY_VPC=false # Override with --only-vpc flag

# Input files
ec2_parameters_file=cloudformation/parameters/ec2-parameters.json
hostname=$(jq -r '.[] | select(.ParameterKey == "HostName") | .ParameterValue' "$ec2_parameters_file")
s3bucket=$(jq -r '.[] | select(.ParameterKey == "BucketName") | .ParameterValue' "$ec2_parameters_file")

# CLI toggle
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=true ;;
    --only-vpc) ONLY_VPC=true ;;
  esac
  shift
done

# Logger
log() {
  echo "$@" >> "$LOG_FILE"
  $VERBOSE && echo "$@" >&2
}

# Stack output printer
print_outputs() {
  [[ "$VERBOSE" == false && "$2" != "always" ]] && return
  echo "$1" | jq -r '.Stacks[].Outputs[] | [.ExportName, .OutputValue] | @tsv' | column -t -N Name,Value
}

# Generic deploy function
deploy_stack() {
  local stack_name="$1"
  local template_file="$2"
  local parameters_file="$3"
  local region="${4:-$AWS_REGION}"
  local opts=()

  [[ -z "$stack_name" || -z "$template_file" || -z "$parameters_file" ]] && {
    echo "Usage: deploy_stack <stack-name> <template-file> <parameters-file> [region]" >&2
    return 1
  }

  if [[ "$stack_name" == "hg-ec2" ]]; then
    log "Uploading EC2-related files to s3://$s3bucket/"
    aws s3 cp ./ec2-files/nginx-proxy.conf s3://"$s3bucket"/nginx-proxy.conf >>"$LOG_FILE" 2>&1
    aws s3 cp ./ec2-files/init.sh s3://"$s3bucket"/init.sh >>"$LOG_FILE" 2>&1
    aws s3 cp ./ec2-files/update-settings.py s3://"$s3bucket"/update-settings.py >>"$LOG_FILE" 2>&1
    opts+=(--capabilities CAPABILITY_NAMED_IAM)
  fi

  readarray -t parameter_overrides < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$parameters_file")

  if [[ ${#parameter_overrides[@]} -eq 0 ]]; then
    log "ERROR: No parameters found in $parameters_file"
    return 1
  fi

  log "Deploying stack: $stack_name with parameters:"
  for param in "${parameter_overrides[@]}"; do
    log "  $param"
  done

  # shellcheck disable=SC2086
  aws cloudformation deploy \
    --stack-name "$stack_name" \
    --template-file "$template_file" \
    --parameter-overrides ${parameter_overrides[@]} \
    --region "$region" \
    "${opts[@]}" >>"$LOG_FILE" 2>&1

  log "Describing outputs for stack: $stack_name"
  aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --region "$region" \
    --output json
}

# VPC Stack
vpc_stack_outputs=$(deploy_stack \
  "hg-vpc" \
  "cloudformation/templates/vpc.yml" \
  "cloudformation/parameters/vpc-parameters.json" \
  "$region")

if [[ "$ONLY_VPC" == true ]]; then
  print_outputs "$vpc_stack_outputs" always
  exit 0
else
  print_outputs "$vpc_stack_outputs"
fi

# Get public IP
log "Detecting your public IP address..."
myip=$(curl -s https://ipinfo.io/ip || true)
if [[ -z "$myip" ]]; then
  echo "Could not get your IP. Exiting." >&2
  exit 1
fi
log "Your IP is: $myip"

# EC2 Stack
ec2_stack_outputs=$(deploy_stack \
  "hg-ec2" \
  "cloudformation/templates/ec2.yml" \
  "$ec2_parameters_file" \
  "$region")

# Get security group from outputs
secgrp=$(echo "$ec2_stack_outputs" | jq -r '.Stacks[0].Outputs[] | select(.ExportName == "prod-cfn-ec2-download-secgrp") | .OutputValue')
log "Using security group ID: $secgrp"

# Open ports for your IP
log "Authorizing SSH and HTTPS access for $myip/32"
aws --region "$region" ec2 authorize-security-group-ingress \
  --group-id "$secgrp" \
  --protocol tcp --port 22 --cidr "${myip}/32" >>"$LOG_FILE" 2>&1

aws --region "$region" ec2 authorize-security-group-ingress \
  --group-id "$secgrp" \
  --protocol tcp --port 443 --cidr "${myip}/32" >>"$LOG_FILE" 2>&1

# Wait for EC2 DNS to be available
echo "Waiting for HTTPS to be available"
while sleep 1; do
  if nc -w 2 -z "$hostname" 443 2>/dev/null; then
    echo -e "\n$(nc -w 2 -vz "$hostname" 443 2>&1)"
    # Revoke port 80 access
    echo -e "\nRevoke port 80... in sec group ${secgrp}"
    aws --region "$region" ec2 revoke-security-group-ingress \
        --group-id "$secgrp" \
        --protocol tcp --port 80 --cidr 0.0.0.0/0 >>"$LOG_FILE" 2>&1
    break
  else
    echo -n "."
  fi
done

print_outputs "$ec2_stack_outputs" always

# Done
echo "Done. Detailed log: $LOG_FILE"
