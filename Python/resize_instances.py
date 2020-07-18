#!/usr/bin/env python
'''
    Module to change the AWS instance types of Tableau Servers for a specific
    build pipeline.  See main() driver function inline comments for each of 
    the steps.

    This version is a first working draft.  Improvements from the code review are
    yet to be implemented.

    11/21/2020 Mikael Sikora
'''

import argparse
import boto3
from botocore.exceptions import ClientError
from botocore.exceptions import WaiterError
import logging
import os
import requests
import sys
import time
import watchtower


def set_arguments():
    """ Defines the list of arguments that can be passed to the routine """
    parser = argparse.ArgumentParser()
    parser.add_argument('-b', "--bucket", default='othello-prod', help="Name of the S3 bucket for SSM documents.",
                        choices=['othello-prod', 'othello-nonprod'])
    parser.add_argument('-L', '--local-mode', action='store_true', help='Specify if you want to run locally.')
    parser.add_argument('-log', "--logging-level", default='INFO', help="Set logging level.",
                        choices=['ERROR', 'INFO', 'DEBUG'])
    parser.add_argument('-p', "--profile-name", default='company-federated', help="Name of the profile used to connect to an AWS account.",
                        choices=['arnawsiam429332399696roleothelloniunonprod', 'arnawsiam183739874660roleothelloniuprod', 'company-federated'])
    parser.add_argument('-pipe', "--pipeline-id", default='CI_PIPELINE_ID', help="Optional override of the pipeline id in case you only want to rerun the configure stage.")
    parser.add_argument('-r', "--region-name", default='us-west-2', help="Name of the target AWS region.",
                        choices=['us-west-2', 'us-east-2'])
    parser.add_argument('-type', "--instance-type", default='m5.2xlarge', help="Set Repository AWS instance type.",
                        choices=['m5.2xlarge', 'm5.4xlarge', 'r5.8xlarge', 'z1d.6xlarge'])

    return parser.parse_args()


def init_logging(log_level, session):
    log_format = '%(asctime)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=log_level, format=log_format)
    global logger
    logger = logging.getLogger(__name__)
    logger.addHandler(watchtower.CloudWatchLogHandler(
        boto3_session=session,
        log_group='TableauCutover',
        stream_name=f'{time.strftime("%Y-%m-%d_%H-%M-%S")}__{os.path.basename(__file__)}',
        send_interval=15
    ))


def get_region():
    r = requests.get(
        'http://169.254.169.254/latest/dynamic/instance-identity/document')
    response_json = r.json()
    return response_json.get('region')


def configure_session(args):
    if not args.region_name and not args.local_mode:
        region_name = get_region()
    else:
        region_name = args.region_name

    if args.local_mode:
        session = boto3.Session(region_name=region_name,
                                profile_name=args.profile_name)
    else:
        session = boto3.Session(region_name=region_name)

    return session


def create_client(session, client_type):
    return session.client(client_type)


def get_ec2_resource(session):
    return session.resource('ec2')


def get_current_ec2():
    response = requests.get("http://169.254.169.254/latest/dynamic/instance-identity/document")
    response_json = response.json()
    return response_json.get('instanceId')


def get_parameter(ssm_client, param_name):
    param_name = ssm_client.get_parameters(Names=[param_name], WithDecryption=True)
    return param_name['Parameters'][0]['Value']


def list_instances_by_tag_value(ec2_client, tagkey, tagvalue):
    # When passed a tag key, tag value this will return a list of
    # InstanceIds that were found.
    instance_list = []
    try:
        response = ec2_client.describe_instances(
            Filters=[{
                    'Name': f'tag:{tagkey}',
                    'Values': [tagvalue]}])
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                instance_id = instance["InstanceId"]
                for tag in instance["Tags"]:
                    if tag["Key"] == "Name":
                        instance_name = tag["Value"]
                instance_list.append([instance_id, instance_name])
    except ClientError as e:
        logger.error(f'ClientError while trying to list instances by tag value:\n{e}')

    return instance_list


def get_all_instances_status(ec2_client, instances):
    all_instances_status = []
    try:
        for this_instance in instances:
            instance_id = this_instance[0]
            response = ec2_client.describe_instance_status(
                InstanceIds=[str(instance_id)],
                IncludeAllInstances=True)
            instance_status = response['InstanceStatuses'][0]['InstanceStatus']['Status']
            system_status = response['InstanceStatuses'][0]['SystemStatus']['Status']
            all_instances_status.append([instance_id, instance_status, system_status])
    except ClientError as e:
        logger.error(f'ClientError while trying to get all instances status:\n{e}')

    return all_instances_status


def get_instance_state(ec2_resource, instance_id, instance_name):
    try:
        instance = ec2_resource.Instance(instance_id)
        instance_state = instance.state.get('Name')
        logger.info(f'Instance {instance_name} is {instance_state}.')
    except ClientError as e:
        logger.error(f'ClientError while trying to get an instance state for {instance_id}:\n{e}')

    return instance_state


def get_all_instances_state(ec2_resource, instances):
    all_instances_state = []
    try:
        for this_instance in instances:
            instance_id = this_instance[0]
            instance = ec2_resource.Instance(instance_id)
            instance_state = instance.state.get('Name')
            all_instances_state.append([instance_id, instance_state])
    except ClientError as e:
        logger.error(f'ClientError while trying to get all instances state:\n{e}')

    return all_instances_state


def stop_instance(ec2_client, instance_id, instance_name):
    try:
        ec2_client.stop_instances(InstanceIds=[instance_id])
        logger.info(f'Instance {instance_name} is stopping.')
        waiter = ec2_client.get_waiter('instance_stopped')
        waiter.wait(InstanceIds=[instance_id])
        logger.info(f'Instance {instance_name} is stopped.')
    except WaiterError as e:
        logger.error(f'WaitError while trying to stop instance {instance_id}:\n{e}')
    except ClientError as e:
        logger.error(f'ClientError while trying to stop instance {instance_id}:\n{e}')


def start_instance(ec2_client, instance_id, instance_name):
    try:
        ec2_client.start_instances(InstanceIds=[instance_id])
        logger.info(f'Instance {instance_name} is starting, waiting until instance_status_ok.')
        waiter = ec2_client.get_waiter('instance_status_ok')
        waiter.wait(InstanceIds=[instance_id])
        logger.info(f'Instance {instance_name} is started.')
    except WaiterError as e:
        logger.error(f'WaitError while trying to stop instance {instance_id}:\n{e}')
    except ClientError as e:
        logger.error(f'ClientError while trying to start instance {instance_id}:\n{e}')


def change_instance_type(ec2_client, instance_id, instance_name, instance_type):
    try:
        ec2_client.modify_instance_attribute(
            InstanceId=instance_id,
            InstanceType={'Value': instance_type})
        logger.info(f'Instance {instance_name} is changed to {instance_type}.')
    except ClientError as e:
        logger.error(f'ClientError while trying to change instance {instance_id} type to {instance_type}:\n{e}')


def get_command_invocation_response_status(ssm_client, command_id, instance_id):
    response = ssm_client.get_command_invocation(
        CommandId=command_id,
        InstanceId=instance_id)
    logger.debug(
        f'The get_command_invocation for command_id {command_id} and instance_id {instance_id} response: {response}')

    response_status = response['Status']
    logger.debug(f'The response_status calculated value: {response_status}')

    if response_status == "Success":
        standard_output_content = response['StandardOutputContent']
        logger.info(f'Standard output: {standard_output_content}')
    elif response_status in ['Pending', 'InProgress', 'Delayed']:
        standard_output_content = response['StandardOutputContent']
        logger.debug(f'Standard output: {standard_output_content}')
    else:
        standard_output_content = response['StandardOutputContent']
        logger.error(f'Standard output: {standard_output_content}')

    return response_status, standard_output_content


def wait_for_command_invocation_success(ssm_client, command_id, instances, loop_limit=60, initial_loop_delay=60,
                                        loop_delay=60):
    loop_instances = instances.copy()
    logger.info(f'Waiting for command invocation success for {command_id} on {loop_instances}.')
    loop = 1
    time.sleep(initial_loop_delay)

    while loop <= loop_limit and loop_instances:
        for instance_id in loop_instances:
            response_status, standard_output_content = get_command_invocation_response_status(ssm_client, command_id,
                                                                                              instance_id)
            if response_status == 'Success':
                logger.info(f'Success for {instance_id}.')
                loop_instances.remove(instance_id)
            elif response_status in ['Pending', 'InProgress', 'Delayed']:
                logger.info(f'Pending for {instance_id}.  Status is {response_status}.')
                time.sleep(loop_delay)
            else:
                raise Exception(f'Error for {instance_id}.  Status is {response_status}.')
            loop += loop

    if loop > loop_limit:
        raise Exception(f'Error for {instance_id}.  SSM document did not return success within time limit.')

    return standard_output_content


def stop_and_delicense_tableau(clients, primary_instance_id, primary_instance_name, s3_bucket):
    # Issue stop command on Primary server
    # ## NEED TO PUT IN CODE TO CAPTURE "Service failed to stop properly" AND CONTINUE
    logger.info(f'Stopping Tableau Server for {primary_instance_name}.')
    response = clients["ssm_client"].send_command(
        InstanceIds=[primary_instance_id],
        DocumentName='TableauServiceStop',
        CloudWatchOutputConfig={
            'CloudWatchLogGroupName': 'TableauCutover',
            'CloudWatchOutputEnabled': True
        }
    )
    logging.debug(f'The send_command for instances {primary_instance_id} response: {response}')
    # Get the command_id so we check the status of the SSM commands.
    command_id = response['Command']['CommandId']
    wait_for_command_invocation_success(clients["ssm_client"], command_id, [primary_instance_id])

    logger.info(f'Deactivating Tableau Server licenses for {primary_instance_name}.')
    response = clients["ssm_client"].send_command(
        InstanceIds=[primary_instance_id],
        DocumentName='TableauDeactivateLicenses',
        Parameters={
            's3Bucket': [s3_bucket]
        },
        CloudWatchOutputConfig={
            'CloudWatchLogGroupName': 'TableauCutover',
            'CloudWatchOutputEnabled': True
        }
    )
    logging.debug(f'The send_command for instances {primary_instance_id} response: {response}')
    # Get the command_id so we check the status of the SSM commands.
    command_id = response['Command']['CommandId']
    wait_for_command_invocation_success(clients["ssm_client"], command_id, [primary_instance_id])


def stop_instances_and_change_instance_type(clients, ec2_resource, instance_type, instances_sorted,
                                            instances_sorted_reduced, instances_sorted_reversed):
    # Stop AWS instances.
    # Using instances_sorted list to ensure that the primary server is stopped first, then workers.
    for this_instance in instances_sorted:
        this_instance_id = this_instance[0]
        this_instance_name = this_instance[1]
        logger.info(f'Stopping instance {this_instance_name}.')
        stop_instance(clients["ec2_client"], this_instance_id, this_instance_name)

    # Change instance type of the instances with repository.
    # Using instances_sorted_reduced ensures that only the instances with repository will changed.
    for this_instance in instances_sorted_reduced:
        this_instance_id = this_instance[0]
        this_instance_name = this_instance[1]
        logger.info(f'Starting instance type change to {instance_type} for {this_instance_name}.')
        change_instance_type(clients["ec2_client"], this_instance_id, this_instance_name, instance_type)

    # Make sure all Worker instances are started before we start Primary, then start Primary.
    # Using instances_sorted_reversed ensures that workers are started first, primary last.
    for this_instance in instances_sorted_reversed:
        this_instance_id = this_instance[0]
        this_instance_name = this_instance[1]
        start_instance(clients["ec2_client"], this_instance_id, this_instance_name)

    # List all instance states
    for this_instance in instances_sorted:
        this_instance_id = this_instance[0]
        this_instance_name = this_instance[1]
        get_instance_state(ec2_resource, this_instance_id, this_instance_name)


def bring_d_drive_online_and_reboot_servers(clients, instances_sorted_reduced):
    # Ensure D: Drive is online for the instances with repository
    for this_instance in instances_sorted_reduced:
        this_instance_id = this_instance[0]
        this_instance_name = this_instance[1]

        # If D: Drive is offline, bring it online
        logger.info(f'Ensure D: Drive is online for {this_instance_name} ({this_instance_id}).')
        response = clients["ssm_client"].send_command(
            InstanceIds=[this_instance_id],
            DocumentName='AWS-RunPowerShellScript',
            Parameters={
                'executionTimeout': ['3600'],
                'commands': ['Set-Disk -Number 1 -IsOffline $False', 'Set-Disk -Number 1 -IsReadonly $False']
            },
            CloudWatchOutputConfig={
                'CloudWatchLogGroupName': 'TableauCutover',
                'CloudWatchOutputEnabled': True
            }
        )
        logging.debug(f'The send_command for instance {this_instance_id} response: {response}')
        # Get the command_id so we check the status of the SSM commands.
        command_id = response['Command']['CommandId']
        wait_for_command_invocation_success(clients["ssm_client"], command_id, [this_instance_id])
        logger.info(f'Completed D: Drive check for {this_instance_name} ({this_instance_id}).')

    # Reboot the servers with instance type change, Primary and Worker 1.
    instance_ids = []
    for this_instance in instances_sorted_reduced:
        instance_ids.append(this_instance[0])

    logger.info(f'Reboot Instances {instances_sorted_reduced}; (Instance IDs {instance_ids}) ).')
    clients["ssm_client"].send_command(
        InstanceIds=instance_ids,
        DocumentName='AWS-RunPowerShellScript',
        Parameters={
            'workingDirectory': ['C:\\cookbooks\\tableau_server\\files'],
            'executionTimeout': ['3600'],
            'commands': ['.\\restart_computer.ps1']
        },
        CloudWatchOutputConfig={
            'CloudWatchLogGroupName': 'TableauStackBuild',
            'CloudWatchOutputEnabled': True
        }
    )
    logger.info(f'Triggered reboot instance {instances_sorted_reduced}) via SSM.')
    logger.info('Sleep three minutes')
    time.sleep(60 * 3)
    logger.info(f'Reboot completed for {instances_sorted_reduced}).')


def license_and_restart_tableau(clients, s3_bucket, primary_instance_id, primary_instance_name):
    # Activate licenses on Primary server
    logger.info(f'Activating Tableau Server licenses for {primary_instance_name}.')
    response = clients["ssm_client"].send_command(
        InstanceIds=[primary_instance_id],
        DocumentName='TableauActivateLicenses',
        Parameters={
            # need to put in variable for prod or nonprod
            's3Bucket': [s3_bucket]
        },
        CloudWatchOutputConfig={
            'CloudWatchLogGroupName': 'TableauCutover',
            'CloudWatchOutputEnabled': True
        }
    )
    logging.debug(f'The send_command for instances {primary_instance_id} response: {response}')
    # Get the command_id so we check the status of the SSM commands.
    command_id = response['Command']['CommandId']
    wait_for_command_invocation_success(clients["ssm_client"], command_id, [primary_instance_id])

    # Issue restart command on Primary TSM service to start the server
    logger.info(f'Restarting Tableau TSM Service for {primary_instance_name}.')
    response = clients["ssm_client"].send_command(
        InstanceIds=[primary_instance_id],
        DocumentName='TableauServiceRestart',
        CloudWatchOutputConfig={
            'CloudWatchLogGroupName': 'TableauCutover',
            'CloudWatchOutputEnabled': True
        }
    )
    logging.debug(f'The send_command for instances {primary_instance_id} response: {response}')
    # Get the command_id so we check the status of the SSM commands.
    command_id = response['Command']['CommandId']
    wait_for_command_invocation_success(clients["ssm_client"], command_id, [primary_instance_id])


def main():
    arguments = set_arguments()
    session = configure_session(arguments)
    init_logging(arguments.logging_level, session)
    ec2_resource = get_ec2_resource(session)
    clients = {
        "ec2_client": create_client(session, 'ec2'),
        "ssm_client": create_client(session, 'ssm')
    }
    instance_type = arguments.instance_type
    s3_bucket = arguments.bucket

    # Get all instances with the current pipeline number.
    stack_tag_name = "stack-pipeline-number"
    instances = list_instances_by_tag_value(clients["ec2_client"], stack_tag_name, arguments.pipeline_id)
    logger.info(f'instances: {instances}')
    instances_sorted = sorted(instances, key=lambda instance: instance[1])

    # Stop Tableau Server and deactivate Tableau Server licenses
    # Need to identify the first element of sorted list 'instances_sorted' as Primary
    # Using first instance of instances_sorted is a cheap way to identify primary.  Ideally, one should check all
    # instance tag "service-role" for Primary.
    primary_instance = instances_sorted[0]
    primary_instance_id = primary_instance[0]
    primary_instance_name = primary_instance[1]
    logger.info(f'Primary instance: {primary_instance}.')

    # Create Worker list the cheap way
    worker_instances = instances_sorted[1:]
    logger.info(f'Worker instances: {worker_instances}.')

    # Create list of the first two instances, Primary and Worker 1.
    # Instances_sorted_reduced is a cheap way to identify what instances to do.  Ideally, one should check for instances
    # with the repository installed, then do those.
    instances_sorted_reduced = instances_sorted[:len(instances_sorted)-2]
    logger.info(f'Instances sorted and reduced: {instances_sorted_reduced}')

    # Create a reversed list, so Workers are started first, then lastly, Primary.
    # We do this the cheap way of reversing the sorted list of instances, making Primary last.
    instances_sorted_reversed = instances_sorted[::-1]
    logger.info(f'Instances sorted reversed: {instances_sorted_reversed}')

    # Check instance health.  If healthy, then stop Tableau Server and deactivate licenses, else bypass.
    all_instances_state = get_all_instances_state(ec2_resource, instances_sorted)
    logger.info(f'Instance State: {all_instances_state}.')
    all_instances_status = get_all_instances_status(clients["ec2_client"], instances_sorted)

    # The following creates a list (ok_instances) from values in elements 1 and 2 of nested list all_instances_status.
    # It basically scrubs the instance ids, element[0], out of the list all_instances_status.
    ok_instances = [[element[1], element[2]] for element in all_instances_status]

    # Check to make sure the string value "ok" is in all the elements of nested list ok_instances.
    # If any of the elements have something other than "ok", then bypass stop_and_delicense_tableau.
    if all('ok' in element for element in ok_instances):
        logger.info(f'All instances are OK: {all_instances_status}.')
        stop_and_delicense_tableau(clients, primary_instance_id, primary_instance_name, s3_bucket)
    else:
        logger.info(f'NOT all instances are OK: {all_instances_status}.  '
                    f'Bypassing Tableau Server stop and license deactivation.')

    # Stop AWS instances, change instance type, then start instances.
    stop_instances_and_change_instance_type(clients, ec2_resource, instance_type, instances_sorted,
                                            instances_sorted_reduced, instances_sorted_reversed)

    # Ensure D: Drive is online and reboot for the instances with repository.
    bring_d_drive_online_and_reboot_servers(clients, instances_sorted_reduced)

    # Activate licenses and restart Tableau Server.
    license_and_restart_tableau(clients, s3_bucket, primary_instance_id, primary_instance_name)

    logger.info(f'Completed the Resize Instances script.')

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical(f"Unhandled exception: {e}", exc_info=True)
        logging.critical("Exiting")
        sys.exit(1)
