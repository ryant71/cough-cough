#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
import socket
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any

# Config
REGION = "eu-west-1"
LOG_FILE = f"/tmp/deploy-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"

# Input files
EC2_PARAMETERS_FILE = "cloudformation/parameters/ec2-parameters.json"


def load_json_parameter(filepath: str, key: str) -> str:
    """Load a specific parameter value from a JSON parameters file."""
    with open(filepath, 'r') as f:
        params = json.load(f)
    for param in params:
        if param.get('ParameterKey') == key:
            return param.get('ParameterValue', '')
    return ''


def log(message: str, verbose: bool = False):
    """Write message to log file and optionally to stderr."""
    with open(LOG_FILE, 'a') as f:
        f.write(f"{message}\n")
    if verbose:
        print(message, file=sys.stderr)


def print_outputs(outputs_json: Dict[str, Any], verbose: bool = False, always: bool = False):
    """Print CloudFormation stack outputs in a formatted table."""
    if not verbose and not always:
        return
    
    try:
        stacks = outputs_json.get('Stacks', [])
        if not stacks:
            return
        
        outputs = stacks[0].get('Outputs', [])
        if outputs:
            print(f"{'Name':<40} {'Value'}")
            print("-" * 80)
            for output in outputs:
                export_name = output.get('ExportName', 'N/A')
                output_value = output.get('OutputValue', 'N/A')
                print(f"{export_name:<40} {output_value}")
    except Exception as e:
        log(f"Error printing outputs: {e}", verbose)


def get_public_ip() -> Optional[str]:
    """Detect the public IP address of this machine."""
    try:
        result = subprocess.run(
            ['curl', '-s', 'https://ipinfo.io/ip'],
            capture_output=True,
            text=True,
            timeout=10
        )
        ip = result.stdout.strip()
        return ip if ip else None
    except Exception:
        return None


def deploy_stack(
    stack_name: str,
    template_file: str,
    parameters_file: str,
    region: str,
    s3bucket: Optional[str] = None,
    verbose: bool = False
) -> Dict[str, Any]:
    """Deploy a CloudFormation stack."""
    
    if not stack_name or not template_file or not parameters_file:
        raise ValueError("stack_name, template_file, and parameters_file are required")
    
    # Load parameters
    with open(parameters_file, 'r') as f:
        params = json.load(f)
    
    if not params:
        log(f"ERROR: No parameters found in {parameters_file}", verbose)
        raise ValueError(f"No parameters in {parameters_file}")
    
    # Build parameter overrides
    parameter_overrides = [f"{p['ParameterKey']}={p['ParameterValue']}" for p in params]
    
    # Special handling for EC2 stack
    capabilities = []
    if stack_name == "hg-ec2" and s3bucket:
        log(f"Uploading EC2-related files to s3://{s3bucket}/", verbose)
        
        files_to_upload = [
            './ec2-files/nginx-proxy.conf',
            './ec2-files/init.sh',
            './ec2-files/update-settings.py',
            './ec2-files/letsencrypt.tgz'
        ]
        
        for file_path in files_to_upload:
            filename = Path(file_path).name
            cmd = ['aws', 's3', 'cp', file_path, f's3://{s3bucket}/{filename}']
            with open(LOG_FILE, 'a') as log_f:
                subprocess.run(cmd, stdout=log_f, stderr=log_f, check=True)
        
        capabilities = ['CAPABILITY_NAMED_IAM']
    
    log(f"Deploying stack: {stack_name} with parameters:", verbose)
    for param in parameter_overrides:
        log(f"  {param}", verbose)
    
    # Build deploy command
    cmd = [
        'aws', 'cloudformation', 'deploy',
        '--stack-name', stack_name,
        '--template-file', template_file,
        '--parameter-overrides', *parameter_overrides,
        '--region', region
    ]
    
    if capabilities:
        cmd.extend(['--capabilities', *capabilities])
    
    # Execute deploy
    subprocess.run(cmd, check=True, stderr=sys.stderr)
    
    # Describe stack outputs
    log(f"Describing outputs for stack: {stack_name}", verbose)
    result = subprocess.run(
        [
            'aws', 'cloudformation', 'describe-stacks',
            '--stack-name', stack_name,
            '--region', region,
            '--output', 'json'
        ],
        capture_output=True,
        text=True,
        check=True
    )
    
    return json.loads(result.stdout)


def check_port_open(hostname: str, port: int, timeout: int = 2) -> bool:
    """Check if a port is open on a hostname."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((hostname, port))
        sock.close()
        return result == 0
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser(description='Deploy AWS CloudFormation stacks')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('--vpc-only', action='store_true', help='Deploy VPC stack only')
    args = parser.parse_args()
    
    verbose = args.verbose
    vpc_only = args.vpc_only
    
    # Load EC2 parameters
    hostname = load_json_parameter(EC2_PARAMETERS_FILE, 'HostName')
    s3bucket = load_json_parameter(EC2_PARAMETERS_FILE, 'BucketName')
    
    # Deploy VPC Stack
    vpc_stack_outputs = deploy_stack(
        "hg-vpc",
        "cloudformation/templates/vpc.yml",
        "cloudformation/parameters/vpc-parameters.json",
        REGION,
        verbose=verbose
    )
    
    if vpc_only:
        print_outputs(vpc_stack_outputs, verbose=verbose, always=True)
        return 0
    else:
        print_outputs(vpc_stack_outputs, verbose=verbose)
    
    print("Begin ec2 deploy")
    
    # Get public IP
    log("Detecting your public IP address...", verbose)
    myip = get_public_ip()
    if not myip:
        print("Could not get your IP. Exiting.", file=sys.stderr)
        return 1
    log(f"Your IP is: {myip}", verbose)
    
    # Deploy EC2 Stack
    ec2_stack_outputs = deploy_stack(
        "hg-ec2",
        "cloudformation/templates/ec2.yml",
        EC2_PARAMETERS_FILE,
        REGION,
        s3bucket=s3bucket,
        verbose=verbose
    )
    
    # Get security group ID from outputs
    secgrp = None
    for output in ec2_stack_outputs['Stacks'][0]['Outputs']:
        if 'secgrp' in output.get('ExportName', '').lower():
            secgrp = output['OutputValue']
            break
    
    log(f"Using security group ID: {secgrp}", verbose)
    
    # Open ports for your IP
    log(f"Authorizing SSH and HTTPS access for {myip}/32", verbose)
    
    with open(LOG_FILE, 'a') as log_f:
        subprocess.run(
            [
                'aws', '--region', REGION, 'ec2', 'authorize-security-group-ingress',
                '--group-id', secgrp,
                '--protocol', 'tcp', '--port', '22', '--cidr', f'{myip}/32'
            ],
            stdout=log_f,
            stderr=log_f
        )
        
        subprocess.run(
            [
                'aws', '--region', REGION, 'ec2', 'authorize-security-group-ingress',
                '--group-id', secgrp,
                '--protocol', 'tcp', '--port', '443', '--cidr', f'{myip}/32'
            ],
            stdout=log_f,
            stderr=log_f
        )
    
    # Get instance public IP
    print("IP")
    result = subprocess.run(
        [
            'aws', 'ec2', 'describe-instances',
            '--filters', 'Name=instance-state-name,Values=running',
            '--query', 'Reservations[*].Instances[*].NetworkInterfaces[*].Association.PublicIp',
            '--output', 'text'
        ],
        capture_output=True,
        text=True
    )
    print(result.stdout)
    
    # Wait for HTTPS to be available
    print("Waiting for HTTPS to be available")
    while True:
        if check_port_open(hostname, 443, timeout=2):
            print(f"\nConnection to {hostname} 443 port [tcp/https] succeeded!")
            
            # Revoke port 80 access
            print(f"\nRevoke port 80... in sec group {secgrp}")
            with open(LOG_FILE, 'a') as log_f:
                subprocess.run(
                    [
                        'aws', '--region', REGION, 'ec2', 'revoke-security-group-ingress',
                        '--group-id', secgrp,
                        '--protocol', 'tcp', '--port', '80', '--cidr', '0.0.0.0/0'
                    ],
                    stdout=log_f,
                    stderr=log_f
                )
            break
        else:
            print(".", end="", flush=True)
            time.sleep(1)
    
    print_outputs(ec2_stack_outputs, verbose=verbose, always=True)
    
    # Download logs
    print("download logs")
    subprocess.run(['aws', 's3', 'cp', f's3://{s3bucket}/setup.log', '.'])
    
    # Check for new letsencrypt tarball
    print("check for new letsencrypt tarball")
    result = subprocess.run(
        ['aws', 's3', 'cp', f's3://{s3bucket}/letsencrypt.tgz', 'ec2-files/letsencrypt.tgz'],
        capture_output=True
    )
    if result.returncode == 0:
        subprocess.run(['aws', 's3', 'rm', f's3://{s3bucket}/letsencrypt.tgz'])
    
    print(f"Done. Detailed log: {LOG_FILE}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
