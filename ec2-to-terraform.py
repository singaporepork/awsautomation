#!/usr/bin/env python3
"""
EC2 to Terraform Converter

Describes an EC2 instance and generates a comprehensive Terraform template
with all instance parameters including metadata configuration, volumes, tags,
network interfaces, and more.

Requirements:
    - Python 3.6 or higher
    - boto3 library (pip install boto3)
    - AWS credentials configured (via AWS CLI, environment variables, or IAM role)

Author: AWS Automation
License: MIT
"""

import argparse
import sys
import json
import base64
from datetime import datetime
from typing import Dict, List, Optional, Any, TextIO
import boto3
from botocore.exceptions import ClientError, NoCredentialsError


class EC2ToTerraform:
    """Convert EC2 instance to Terraform configuration."""

    def __init__(self, region: str, instance_id: str, profile: Optional[str] = None):
        """
        Initialize the EC2 to Terraform converter.

        Args:
            region: AWS region name (e.g., 'us-east-1')
            instance_id: EC2 instance ID (e.g., 'i-1234567890abcdef0')
            profile: AWS CLI profile name (optional)
        """
        self.region = region
        self.instance_id = instance_id
        self.profile = profile
        self.session = self._create_session()
        self.ec2_client = self.session.client('ec2', region_name=region)
        self.ec2_resource = self.session.resource('ec2', region_name=region)
        self.instance_data = None
        self.volumes_data = []
        self.network_interfaces_data = []
        self.elastic_ips_data = []

    def _create_session(self) -> boto3.Session:
        """Create and return a boto3 session."""
        if self.profile:
            return boto3.Session(profile_name=self.profile, region_name=self.region)
        return boto3.Session(region_name=self.region)

    def describe_instance(self) -> Dict[str, Any]:
        """
        Describe the EC2 instance and retrieve all details.

        Returns:
            Dictionary containing instance details

        Raises:
            SystemExit: If instance not found or API error occurs
        """
        print(f"Describing instance {self.instance_id} in {self.region}...")

        try:
            response = self.ec2_client.describe_instances(InstanceIds=[self.instance_id])

            if not response['Reservations']:
                print(f"Error: Instance {self.instance_id} not found in {self.region}", file=sys.stderr)
                sys.exit(1)

            instance = response['Reservations'][0]['Instances'][0]
            self.instance_data = instance

            # Get additional instance attribute details
            self._get_instance_attributes()

            # Get volume details
            self._get_volume_details()

            # Get network interface details
            self._get_network_interface_details()

            # Get Elastic IP details
            self._get_elastic_ip_details()

            print(f"Successfully retrieved instance details")
            print(f"  Instance Type: {instance.get('InstanceType', 'N/A')}")
            print(f"  State: {instance.get('State', {}).get('Name', 'N/A')}")
            print(f"  AMI: {instance.get('ImageId', 'N/A')}")
            print(f"  VPC: {instance.get('VpcId', 'N/A')}")
            print(f"  Subnet: {instance.get('SubnetId', 'N/A')}")

            return instance

        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_msg = e.response['Error']['Message']

            if error_code == 'InvalidInstanceID.NotFound':
                print(f"Error: Instance {self.instance_id} not found", file=sys.stderr)
            else:
                print(f"Error: {error_code} - {error_msg}", file=sys.stderr)

            sys.exit(1)

        except NoCredentialsError:
            print("Error: AWS credentials not found", file=sys.stderr)
            print("Configure credentials using 'aws configure' or set environment variables", file=sys.stderr)
            sys.exit(1)

    def _get_instance_attributes(self) -> None:
        """Get additional instance attributes not included in describe_instances."""
        try:
            # Get user data
            user_data_response = self.ec2_client.describe_instance_attribute(
                InstanceId=self.instance_id,
                Attribute='userData'
            )
            self.instance_data['UserDataAttribute'] = user_data_response.get('UserData', {})

            # Get source/dest check
            src_dst_response = self.ec2_client.describe_instance_attribute(
                InstanceId=self.instance_id,
                Attribute='sourceDestCheck'
            )
            self.instance_data['SourceDestCheckAttribute'] = src_dst_response.get('SourceDestCheck', {})

            # Get disable API termination
            termination_response = self.ec2_client.describe_instance_attribute(
                InstanceId=self.instance_id,
                Attribute='disableApiTermination'
            )
            self.instance_data['DisableApiTerminationAttribute'] = termination_response.get('DisableApiTermination', {})

        except ClientError as e:
            print(f"Warning: Could not retrieve some instance attributes: {e}", file=sys.stderr)

    def _get_volume_details(self) -> None:
        """Get detailed information about attached volumes."""
        block_devices = self.instance_data.get('BlockDeviceMappings', [])

        for bd in block_devices:
            volume_id = bd.get('Ebs', {}).get('VolumeId')
            if volume_id:
                try:
                    volume_response = self.ec2_client.describe_volumes(VolumeIds=[volume_id])
                    if volume_response['Volumes']:
                        self.volumes_data.append(volume_response['Volumes'][0])
                except ClientError as e:
                    print(f"Warning: Could not retrieve volume {volume_id}: {e}", file=sys.stderr)

    def _get_network_interface_details(self) -> None:
        """Get detailed information about network interfaces."""
        for ni in self.instance_data.get('NetworkInterfaces', []):
            ni_id = ni.get('NetworkInterfaceId')
            if ni_id:
                try:
                    ni_response = self.ec2_client.describe_network_interfaces(
                        NetworkInterfaceIds=[ni_id]
                    )
                    if ni_response['NetworkInterfaces']:
                        self.network_interfaces_data.append(ni_response['NetworkInterfaces'][0])
                except ClientError as e:
                    print(f"Warning: Could not retrieve network interface {ni_id}: {e}", file=sys.stderr)

    def _get_elastic_ip_details(self) -> None:
        """Get Elastic IP associations for this instance."""
        try:
            eip_response = self.ec2_client.describe_addresses(
                Filters=[
                    {'Name': 'instance-id', 'Values': [self.instance_id]}
                ]
            )
            self.elastic_ips_data = eip_response.get('Addresses', [])
        except ClientError as e:
            print(f"Warning: Could not retrieve Elastic IPs: {e}", file=sys.stderr)

    def _get_tag_value(self, tags: List[Dict[str, str]], key: str) -> Optional[str]:
        """Get tag value by key."""
        for tag in tags:
            if tag.get('Key') == key:
                return tag.get('Value')
        return None

    def _sanitize_resource_name(self, name: str) -> str:
        """
        Sanitize a name to be valid for Terraform resource names.

        Args:
            name: Original name

        Returns:
            Sanitized name valid for Terraform
        """
        # Replace invalid characters with underscores
        sanitized = ''.join(c if c.isalnum() or c == '_' else '_' for c in name)
        # Ensure it starts with a letter or underscore
        if sanitized and sanitized[0].isdigit():
            sanitized = '_' + sanitized
        return sanitized.lower() if sanitized else 'instance'

    def _format_tags(self, tags: List[Dict[str, str]], indent: int = 2) -> str:
        """
        Format tags for Terraform.

        Args:
            tags: List of tag dictionaries
            indent: Number of spaces for indentation

        Returns:
            Formatted tags string
        """
        if not tags:
            return f"{' ' * indent}tags = {{}}"

        lines = [f"{' ' * indent}tags = {{"]
        for tag in tags:
            key = tag.get('Key', '')
            value = tag.get('Value', '').replace('"', '\\"')
            lines.append(f'{" " * (indent + 2)}{key} = "{value}"')
        lines.append(f"{' ' * indent}}}")
        return '\n'.join(lines)

    def generate_terraform(self, output_file: Optional[str] = None) -> str:
        """
        Generate Terraform configuration from instance details.

        Args:
            output_file: Optional output file path

        Returns:
            Generated Terraform configuration as string
        """
        if not self.instance_data:
            print("Error: No instance data available. Call describe_instance() first.", file=sys.stderr)
            sys.exit(1)

        print("\nGenerating Terraform configuration...")

        tf_config = []

        # Add header comment
        tf_config.append(self._generate_header())

        # Generate main instance resource
        tf_config.append(self._generate_instance_resource())

        # Generate additional EBS volumes (non-root)
        ebs_volumes = self._generate_ebs_volumes()
        if ebs_volumes:
            tf_config.append(ebs_volumes)

        # Generate volume attachments
        volume_attachments = self._generate_volume_attachments()
        if volume_attachments:
            tf_config.append(volume_attachments)

        # Generate Elastic IP resources
        eip_resources = self._generate_elastic_ip_resources()
        if eip_resources:
            tf_config.append(eip_resources)

        # Generate additional network interfaces (non-primary)
        network_interfaces = self._generate_network_interfaces()
        if network_interfaces:
            tf_config.append(network_interfaces)

        # Add variables file recommendation
        tf_config.append(self._generate_variables_recommendation())

        full_config = '\n\n'.join(tf_config)

        # Write to file if specified
        if output_file:
            try:
                with open(output_file, 'w', encoding='utf-8') as f:
                    f.write(full_config)
                print(f"\nTerraform configuration written to: {output_file}")
            except IOError as e:
                print(f"Error writing to file: {e}", file=sys.stderr)
                sys.exit(1)

        return full_config

    def _generate_header(self) -> str:
        """Generate header comment for Terraform file."""
        instance_name = self._get_tag_value(self.instance_data.get('Tags', []), 'Name') or self.instance_id

        return f"""# Terraform configuration generated from EC2 instance
# Generated: {datetime.utcnow().isoformat()}Z
# Source Instance: {self.instance_id}
# Instance Name: {instance_name}
# Region: {self.region}
#
# NOTE: This is a generated configuration. Review and customize as needed.
# Some values may need to be parameterized or adjusted for your use case."""

    def _generate_instance_resource(self) -> str:
        """Generate the main aws_instance resource."""
        instance = self.instance_data
        tags = instance.get('Tags', [])
        instance_name = self._get_tag_value(tags, 'Name') or self.instance_id
        resource_name = self._sanitize_resource_name(instance_name)

        lines = [
            f'resource "aws_instance" "{resource_name}" {{',
            f'  ami           = "{instance.get("ImageId", "")}"',
            f'  instance_type = "{instance.get("InstanceType", "")}"'
        ]

        # Key pair
        if instance.get('KeyName'):
            lines.append(f'  key_name      = "{instance["KeyName"]}"')

        # Availability zone
        if instance.get('Placement', {}).get('AvailabilityZone'):
            lines.append(f'  availability_zone = "{instance["Placement"]["AvailabilityZone"]}"')

        # Subnet
        if instance.get('SubnetId'):
            lines.append(f'  subnet_id     = "{instance["SubnetId"]}"')

        # VPC Security Groups
        if instance.get('SecurityGroups') or instance.get('NetworkInterfaces', [{}])[0].get('Groups'):
            # For instances in VPC, security groups are in network interfaces
            sg_ids = []
            if instance.get('NetworkInterfaces'):
                for group in instance['NetworkInterfaces'][0].get('Groups', []):
                    sg_ids.append(group['GroupId'])
            elif instance.get('SecurityGroups'):
                # For EC2-Classic
                sg_ids = [sg['GroupId'] for sg in instance['SecurityGroups']]

            if sg_ids:
                lines.append(f'  vpc_security_group_ids = {json.dumps(sg_ids)}')

        # Private IP (primary network interface)
        if instance.get('PrivateIpAddress'):
            lines.append(f'  private_ip    = "{instance["PrivateIpAddress"]}"')

        # IAM Instance Profile
        if instance.get('IamInstanceProfile'):
            iam_profile_arn = instance['IamInstanceProfile'].get('Arn', '')
            # Extract profile name from ARN
            iam_profile_name = iam_profile_arn.split('/')[-1] if iam_profile_arn else ''
            if iam_profile_name:
                lines.append(f'  iam_instance_profile = "{iam_profile_name}"')

        # Source/Dest Check
        src_dst_check = self.instance_data.get('SourceDestCheckAttribute', {}).get('Value', True)
        if not src_dst_check:
            lines.append(f'  source_dest_check = false')

        # Monitoring (detailed monitoring)
        if instance.get('Monitoring', {}).get('State') == 'enabled':
            lines.append(f'  monitoring = true')

        # EBS Optimized
        if instance.get('EbsOptimized'):
            lines.append(f'  ebs_optimized = true')

        # Disable API Termination
        disable_api_termination = self.instance_data.get('DisableApiTerminationAttribute', {}).get('Value', False)
        if disable_api_termination:
            lines.append(f'  disable_api_termination = true')

        # Tenancy
        if instance.get('Placement', {}).get('Tenancy') and instance['Placement']['Tenancy'] != 'default':
            lines.append(f'  tenancy = "{instance["Placement"]["Tenancy"]}"')

        # Placement Group
        if instance.get('Placement', {}).get('GroupName'):
            lines.append(f'  placement_group = "{instance["Placement"]["GroupName"]}"')

        # Host ID (for dedicated hosts)
        if instance.get('Placement', {}).get('HostId'):
            lines.append(f'  host_id = "{instance["Placement"]["HostId"]}"')

        # CPU Credits (for T-series instances)
        if instance.get('CreditSpecification'):
            cpu_credits = instance['CreditSpecification'].get('CpuCredits', '')
            if cpu_credits:
                lines.append(f'\n  credit_specification {{')
                lines.append(f'    cpu_credits = "{cpu_credits}"')
                lines.append(f'  }}')

        # Metadata Options
        if instance.get('MetadataOptions'):
            lines.append(f'\n  metadata_options {{')
            metadata = instance['MetadataOptions']

            if metadata.get('HttpEndpoint'):
                lines.append(f'    http_endpoint               = "{metadata["HttpEndpoint"]}"')
            if metadata.get('HttpTokens'):
                lines.append(f'    http_tokens                 = "{metadata["HttpTokens"]}"')
            if metadata.get('HttpPutResponseHopLimit'):
                lines.append(f'    http_put_response_hop_limit = {metadata["HttpPutResponseHopLimit"]}')
            if metadata.get('InstanceMetadataTags'):
                lines.append(f'    instance_metadata_tags      = "{metadata["InstanceMetadataTags"]}"')

            lines.append(f'  }}')

        # Enclave Options
        if instance.get('EnclaveOptions', {}).get('Enabled'):
            lines.append(f'\n  enclave_options {{')
            lines.append(f'    enabled = true')
            lines.append(f'  }}')

        # Capacity Reservation
        if instance.get('CapacityReservationSpecification'):
            cap_res = instance['CapacityReservationSpecification']
            if cap_res.get('CapacityReservationPreference'):
                lines.append(f'\n  capacity_reservation_specification {{')
                lines.append(f'    capacity_reservation_preference = "{cap_res["CapacityReservationPreference"]}"')
                lines.append(f'  }}')

        # Hibernation
        if instance.get('HibernationOptions', {}).get('Configured'):
            lines.append(f'\n  hibernation = true')

        # User Data
        user_data_attr = self.instance_data.get('UserDataAttribute', {})
        if user_data_attr.get('Value'):
            user_data_encoded = user_data_attr['Value']
            # User data is base64 encoded in the response
            # We'll reference it as base64-encoded in Terraform
            lines.append(f'\n  # User data (base64 encoded)')
            lines.append(f'  user_data_base64 = "{user_data_encoded}"')

            # Optionally decode and show as comment
            try:
                user_data_decoded = base64.b64decode(user_data_encoded).decode('utf-8')
                if len(user_data_decoded) < 500:  # Only show if reasonably sized
                    lines.append(f'  # Decoded user data:')
                    for line in user_data_decoded.split('\n'):
                        lines.append(f'  # {line}')
            except Exception:
                pass

        # Root Block Device
        root_device_name = instance.get('RootDeviceName')
        if root_device_name:
            root_volume = None
            for bd in instance.get('BlockDeviceMappings', []):
                if bd.get('DeviceName') == root_device_name:
                    root_volume = bd.get('Ebs', {})
                    break

            if root_volume:
                lines.append(f'\n  root_block_device {{')

                # Find the volume details
                volume_id = root_volume.get('VolumeId')
                volume_details = None
                for vol in self.volumes_data:
                    if vol['VolumeId'] == volume_id:
                        volume_details = vol
                        break

                if volume_details:
                    lines.append(f'    volume_type           = "{volume_details.get("VolumeType", "gp2")}"')
                    lines.append(f'    volume_size           = {volume_details.get("Size", 8)}')

                    if volume_details.get('Iops'):
                        lines.append(f'    iops                  = {volume_details["Iops"]}')
                    if volume_details.get('Throughput'):
                        lines.append(f'    throughput            = {volume_details["Throughput"]}')
                    if volume_details.get('Encrypted'):
                        lines.append(f'    encrypted             = true')
                    if volume_details.get('KmsKeyId'):
                        lines.append(f'    kms_key_id            = "{volume_details["KmsKeyId"]}"')

                delete_on_termination = root_volume.get('DeleteOnTermination', True)
                lines.append(f'    delete_on_termination = {str(delete_on_termination).lower()}')

                # Add volume tags
                if volume_details and volume_details.get('Tags'):
                    tag_lines = self._format_tags(volume_details['Tags'], indent=4)
                    lines.append(f'\n{tag_lines}')

                lines.append(f'  }}')

        # Additional EBS Block Devices (attached at launch, not separate attachments)
        ebs_devices = []
        for bd in instance.get('BlockDeviceMappings', []):
            if bd.get('DeviceName') != root_device_name and bd.get('Ebs'):
                ebs_devices.append(bd)

        for bd in ebs_devices:
            device_name = bd['DeviceName']
            ebs_info = bd['Ebs']
            volume_id = ebs_info.get('VolumeId')

            # Find volume details
            volume_details = None
            for vol in self.volumes_data:
                if vol['VolumeId'] == volume_id:
                    volume_details = vol
                    break

            lines.append(f'\n  ebs_block_device {{')
            lines.append(f'    device_name           = "{device_name}"')

            if volume_details:
                lines.append(f'    volume_type           = "{volume_details.get("VolumeType", "gp2")}"')
                lines.append(f'    volume_size           = {volume_details.get("Size", 8)}')

                if volume_details.get('Iops'):
                    lines.append(f'    iops                  = {volume_details["Iops"]}')
                if volume_details.get('Throughput'):
                    lines.append(f'    throughput            = {volume_details["Throughput"]}')
                if volume_details.get('Encrypted'):
                    lines.append(f'    encrypted             = true')
                if volume_details.get('KmsKeyId'):
                    lines.append(f'    kms_key_id            = "{volume_details["KmsKeyId"]}"')

                # Add volume tags
                if volume_details.get('Tags'):
                    tag_lines = self._format_tags(volume_details['Tags'], indent=4)
                    lines.append(f'\n{tag_lines}')

            delete_on_termination = ebs_info.get('DeleteOnTermination', True)
            lines.append(f'    delete_on_termination = {str(delete_on_termination).lower()}')

            lines.append(f'  }}')

        # Ephemeral Block Devices (Instance Store)
        for bd in instance.get('BlockDeviceMappings', []):
            if bd.get('VirtualName'):  # Instance store volumes have VirtualName
                lines.append(f'\n  ephemeral_block_device {{')
                lines.append(f'    device_name  = "{bd["DeviceName"]}"')
                lines.append(f'    virtual_name = "{bd["VirtualName"]}"')
                lines.append(f'  }}')

        # Network Interface (only if NOT using the default)
        # We skip this for simplicity as most configs use subnet_id + security groups
        # Complex network interface configurations would be in separate resources

        # Tags
        if tags:
            lines.append(f'\n{self._format_tags(tags)}')

        # Volume tags (if different from instance tags)
        lines.append(f'\n  # Set volume_tags if you want different tags for volumes')
        lines.append(f'  # volume_tags = {{}}')

        # Lifecycle
        lines.append(f'\n  lifecycle {{')
        lines.append(f'    # Prevent accidental instance replacement')
        lines.append(f'    # ignore_changes = [ami, user_data]')
        lines.append(f'  }}')

        lines.append('}')

        return '\n'.join(lines)

    def _generate_ebs_volumes(self) -> str:
        """Generate separate EBS volume resources (for volumes attached separately)."""
        # For now, we'll skip this as most volumes are defined inline in the instance
        # This would be used for volumes that are managed separately
        return ""

    def _generate_volume_attachments(self) -> str:
        """Generate EBS volume attachment resources."""
        # For volumes managed separately from the instance
        return ""

    def _generate_elastic_ip_resources(self) -> str:
        """Generate Elastic IP and association resources."""
        if not self.elastic_ips_data:
            return ""

        lines = []
        instance = self.instance_data
        tags = instance.get('Tags', [])
        instance_name = self._get_tag_value(tags, 'Name') or self.instance_id
        resource_name = self._sanitize_resource_name(instance_name)

        for i, eip in enumerate(self.elastic_ips_data):
            eip_name = f"{resource_name}_eip_{i}" if i > 0 else f"{resource_name}_eip"

            lines.append(f'# Elastic IP for {instance_name}')
            lines.append(f'resource "aws_eip" "{eip_name}" {{')
            lines.append(f'  domain = "vpc"')

            # EIP tags
            if eip.get('Tags'):
                lines.append(f'\n{self._format_tags(eip["Tags"])}')

            lines.append(f'}}')
            lines.append(f'')
            lines.append(f'resource "aws_eip_association" "{eip_name}_assoc" {{')
            lines.append(f'  instance_id   = aws_instance.{resource_name}.id')
            lines.append(f'  allocation_id = aws_eip.{eip_name}.id')
            lines.append(f'}}')

        return '\n'.join(lines) if lines else ""

    def _generate_network_interfaces(self) -> str:
        """Generate additional network interface resources (non-primary)."""
        # Skip primary network interface as it's managed by the instance resource
        # Additional ENIs would be generated here
        if len(self.network_interfaces_data) <= 1:
            return ""

        lines = []
        instance = self.instance_data
        tags = instance.get('Tags', [])
        instance_name = self._get_tag_value(tags, 'Name') or self.instance_id
        resource_name = self._sanitize_resource_name(instance_name)

        # Sort by attachment index
        sorted_enis = sorted(
            self.network_interfaces_data,
            key=lambda x: x.get('Attachment', {}).get('DeviceIndex', 999)
        )

        for eni in sorted_enis[1:]:  # Skip first (primary) ENI
            device_index = eni.get('Attachment', {}).get('DeviceIndex', 0)
            eni_name = f"{resource_name}_eni_{device_index}"

            lines.append(f'# Additional Network Interface (device index {device_index})')
            lines.append(f'resource "aws_network_interface" "{eni_name}" {{')
            lines.append(f'  subnet_id       = "{eni.get("SubnetId", "")}"')

            # Security groups
            if eni.get('Groups'):
                sg_ids = [g['GroupId'] for g in eni['Groups']]
                lines.append(f'  security_groups = {json.dumps(sg_ids)}')

            # Private IPs
            if eni.get('PrivateIpAddresses'):
                private_ips = [ip['PrivateIpAddress'] for ip in eni['PrivateIpAddresses']]
                if private_ips:
                    lines.append(f'  private_ips     = {json.dumps(private_ips)}')

            # Source/Dest Check
            if not eni.get('SourceDestCheck', True):
                lines.append(f'  source_dest_check = false')

            # Tags
            if eni.get('TagSet'):
                lines.append(f'\n{self._format_tags(eni["TagSet"])}')

            lines.append(f'}}')
            lines.append(f'')
            lines.append(f'resource "aws_network_interface_attachment" "{eni_name}_attach" {{')
            lines.append(f'  instance_id          = aws_instance.{resource_name}.id')
            lines.append(f'  network_interface_id = aws_network_interface.{eni_name}.id')
            lines.append(f'  device_index         = {device_index}')
            lines.append(f'}}')
            lines.append(f'')

        return '\n'.join(lines) if lines else ""

    def _generate_variables_recommendation(self) -> str:
        """Generate recommendation for variables file."""
        return """# Recommendations:
# 1. Consider parameterizing values like AMI ID, instance type, etc. using variables
# 2. Use data sources to look up existing resources (VPCs, subnets, security groups)
# 3. Review all settings and adjust for your specific requirements
# 4. Test this configuration in a non-production environment first
# 5. Consider using remote state and proper state management
#
# Example variables you might want to create:
# - var.instance_type
# - var.ami_id
# - var.key_name
# - var.subnet_id
# - var.security_group_ids"""

    def export_json(self, output_file: str) -> None:
        """
        Export raw instance details to JSON file.

        Args:
            output_file: Output JSON file path
        """
        if not self.instance_data:
            print("Error: No instance data available.", file=sys.stderr)
            return

        export_data = {
            'metadata': {
                'export_date': datetime.utcnow().isoformat() + 'Z',
                'instance_id': self.instance_id,
                'region': self.region
            },
            'instance': self.instance_data,
            'volumes': self.volumes_data,
            'network_interfaces': self.network_interfaces_data,
            'elastic_ips': self.elastic_ips_data
        }

        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(export_data, f, indent=2, default=str)
            print(f"Instance details exported to JSON: {output_file}")
        except IOError as e:
            print(f"Error writing JSON file: {e}", file=sys.stderr)


def main():
    """Main function to parse arguments and generate Terraform configuration."""
    parser = argparse.ArgumentParser(
        description='Convert EC2 instance to Terraform configuration',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate Terraform config for an instance
  %(prog)s --region us-east-1 --instance-id i-1234567890abcdef0

  # Save to specific output file
  %(prog)s --region us-east-1 --instance-id i-1234567890abcdef0 --output instance.tf

  # Export raw JSON data as well
  %(prog)s --region us-east-1 --instance-id i-1234567890abcdef0 --output instance.tf --json instance.json

  # Use specific AWS profile
  %(prog)s --region us-west-2 --instance-id i-abcdef1234567890 --profile production

  # Print to stdout
  %(prog)s --region eu-west-1 --instance-id i-0987654321fedcba
        """
    )

    parser.add_argument(
        '--region',
        required=True,
        help='AWS region (e.g., us-east-1, us-west-2)'
    )

    parser.add_argument(
        '--instance-id',
        required=True,
        help='EC2 instance ID (e.g., i-1234567890abcdef0)'
    )

    parser.add_argument(
        '--output',
        help='Output Terraform file path (default: print to stdout)'
    )

    parser.add_argument(
        '--json',
        help='Also export raw instance details to JSON file'
    )

    parser.add_argument(
        '--profile',
        help='AWS CLI profile name to use'
    )

    args = parser.parse_args()

    # Create converter
    converter = EC2ToTerraform(
        region=args.region,
        instance_id=args.instance_id,
        profile=args.profile
    )

    # Describe the instance
    converter.describe_instance()

    # Generate Terraform configuration
    tf_config = converter.generate_terraform(output_file=args.output)

    # Print to stdout if no output file specified
    if not args.output:
        print("\n" + "=" * 60)
        print("GENERATED TERRAFORM CONFIGURATION")
        print("=" * 60 + "\n")
        print(tf_config)

    # Export JSON if requested
    if args.json:
        converter.export_json(args.json)

    print("\nDone!")


if __name__ == '__main__':
    main()
