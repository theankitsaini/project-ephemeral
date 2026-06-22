import boto3

ec2 = boto3.client('ec2', region_name='eu-west-1')

def lambda_handler(event, context):
    # Search for instances with the specific environment tag
    filters = [{'Name': 'tag:Environment', 'Values': ['Ephemeral-Project']}]
    
    instances = ec2.describe_instances(Filters=filters)
    instance_ids = []
    
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])
            
    if instance_ids:
        ec2.stop_instances(InstanceIds=instance_ids)
        print(f"Successfully stopped instances: {instance_ids}")
    else:
        print("No active Ephemeral instances found to stop.")