#!/usr/bin/env python3

"""
Pretty much does the same thing as:

aws ec2 describe-instances \
    --query "Reservations[*].Instances[0].[KeyName,PrivateIpAddress,LaunchTime,State.Name]" \
    --output table

... except it prints out all tags in a shwanky table

Requires:
    pip install boto3 textual

"""

import boto3

from itertools import cycle

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import DataTable

# Initialize the Boto3 RDS client
ec2_client = boto3.client('ec2')

instance_attributes = [
    'InstanceId',
    'InstanceType',
    'PrivateIpAddress',
    'PublicIpAddress',
    'LaunchTime',
    'State.Name',
]

tag_keys = ['Name']


def make_ec2_attribute_dict(ec2_instance):
    _dict = {}
    for attribute in instance_attributes:
        back = ''
        front = ''
        print(f'{attribute} + {back}')
        if attribute.find('.') >= 1:
            front = attribute.split('.')[0]
            back = attribute.split('.')[1]
            print(f'eeek {front} + {back}')
        try:
            if back:
                try:
                    _ret = dict(ec2_instance[front])
                    _dict[attribute] = _ret[back]
                except TypeError:
                    _dict[attribute] = ec2_instance[front]
            else:
                _dict[attribute] = ec2_instance[attribute]
        except KeyError:
            _dict[attribute] = '-'
    return _dict


def make_ec2_tag_dict(ec2_instance):
    return {t['Key']: t['Value'] for t in ec2_instance.get('Tags', [])}


def make_ec2_dict():
    response = ec2_client.describe_instances()
    identifier_tag_list = []
    for reservations in response['Reservations']:
        for ec2_instance in reservations['Instances']:
            instance_dict = {}
            instance_dict.update(make_ec2_tag_dict(ec2_instance))
            instance_dict.update(make_ec2_attribute_dict(ec2_instance))
            identifier_tag_list.append(instance_dict)
    return identifier_tag_list


def make_attribute_matrix(dict_list):
    search_keys = tag_keys + instance_attributes
    list_of_lists = [search_keys]
    for _dict in dict_list:
        sublist = []
        for search_key in search_keys:
            if search_key not in _dict.keys():
                _dict[search_key] = '*MISSING*'
            for dict_key in _dict.keys():
                if dict_key == search_key:
                    sublist.append(_dict[dict_key])
        list_of_lists.append(sublist)
    return list_of_lists


class TableApp(App):

    # Add vi key maps
    # - not working yet
    BINDINGS = [
        Binding("h", "left", "<", show=True, priority=True),
        Binding("j", "down", "v", priority=True),
        Binding("k", "cursor_up", "^", priority=True),
        Binding("l", "cursor_right", ">", priority=True),
    ]

    def compose(self) -> ComposeResult:
        yield DataTable()

    def on_mount(self) -> None:
        table = self.query_one(DataTable)
        table.cursor_type = next(cursors)
        table.zebra_stripes = True
        table.add_columns(*the_matrix[0])
        table.add_rows(the_matrix[1:])

    def key_c(self):
        table = self.query_one(DataTable)
        table.cursor_type = next(cursors)

    def on_key(self, event):
        """Handle key presses"""
        if event.key == "q":
            self.exit()


the_matrix = make_attribute_matrix(make_ec2_dict())

cursors = cycle(["row", "column", "cell"])

app = TableApp()
if __name__ == "__main__":
    app.run()
