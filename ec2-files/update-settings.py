#!/usr/bin/env python3

import json
import sys
import os


def update_json_file(file_path, updates):
    """
    Updates a JSON file with the given key-value pairs.

    Args:
        file_path (str): Path to the JSON file.
        updates (dict): Key-value pairs to update/add to the JSON file.

    Returns:
        None
    """
    # Load existing data if the file exists, otherwise use an empty dictionary
    if os.path.exists(file_path):
        with open(file_path, 'r') as file:
            try:
                data = json.load(file)
            except json.JSONDecodeError:
                print(f"Warning: {file_path} is not a valid JSON file. Starting with an empty dictionary.")
                data = {}
    else:
        data = {}

    # Update the data with the provided key-value pairs
    data.update(updates)

    # Save the updated data back to the file
    with open(file_path, 'w') as file:
        json.dump(data, file, indent=4)

    print(f"Successfully updated {file_path}.")


if __name__ == "__main__":

    # Define the path to your JSON file
    try:
        json_file_path = sys.argv[1]
    except IndexError:
        json_file_path = "/home/ubuntu/.config/transmission-daemon/settings.json"

    # Define the key-value pairs to update/add
    updates_to_apply = {
        "download-dir": "/home/ubuntu/Downloads",
        "incomplete-dir": "/home/ubuntu/incomplete-dir",
        "incomplete-dir-enabled": True,
        "download-queue-size": 1,
        "encryption": 2,
        "idle-seeding-limit": 20,
        "idle-seeding-limit-enabled": True,
        "peer-port": "51304",
        "peer-port-random-on-start": True,
        "peer-port-random-low": 49152,
        "peer-port-random-high": 65535,
        "ratio-limit": 1,
        "ratio-limit-enabled": True,
        "rename-partial-files": True,
        "speed-limit-up-enabled": True,
        "speed-limit-up": 50,
        "rpc-host-whitelist-enabled": False,
        "rpc-whitelist-enabled": False,
    }

    # Update the JSON file
    update_json_file(json_file_path, updates_to_apply)
