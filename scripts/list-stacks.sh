#!/usr/bin/env bash
aws cloudformation list-stacks --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].[StackName,StackStatus,CreationTime,LastUpdatedTime]" --output table
