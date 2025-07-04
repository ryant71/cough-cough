#!/usr/bin/env bash
aws ec2 describe-instances --query "Reservations[*].Instances[0].[KeyName,PrivateIpAddress,LaunchTime,State.Name]" --output table
