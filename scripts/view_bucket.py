#!/usr/bin/env python3

import boto3
import humanize

client = boto3.client("s3")

for bucket in client.list_buckets()['Buckets']:
    if bucket['Name'].startswith('cfn-content'):
        bucket_name = bucket['Name']
        break

print(bucket_name)
objects = client.list_objects(Bucket=bucket_name)

for obj_path in objects['Contents']:
    obj = client.get_object(Bucket=bucket_name, Key=obj_path['Key'])

    if obj['ContentType'] == 'application/x-directory':
        continue

    content_length = obj['ContentLength']
    size = humanize.naturalsize(content_length)
    print(f"{size:<10} {obj_path['Key']}")
