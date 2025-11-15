#!/usr/bin/env python3
"""
Elastic IP Cleanup Script

Identifies and optionally releases Elastic IP addresses that are not associated
with any EC2 instances or network interfaces across all AWS regions. Unassociated
Elastic IPs incur charges without providing value.

Author: AWS Automation
License: MIT
"""

import boto3
import json
import argparse
import sys
from datetime import datetime
from typing import List, Dict, Any, Optional
from botocore.exceptions import ClientError, BotoCoreError


class ElasticIPCleanup:
    """Main class for Elastic IP cleanup operations."""

    def __init__(self, profile: Optional[str] = None, dry_run: bool = True, regions: Optional[List[str]] = None):
        """
        Initialize the Elastic IP cleanup tool.

        Args:
            profile: AWS profile name to use
            dry_run: If True, only report what would be released without actually releasing
            regions: List of specific regions to check (if None, checks all enabled regions)
        """
        self.session = boto3.Session(profile_name=profile) if profile else boto3.Session()
        self.dry_run = dry_run
        self.specified_regions = regions
        self.unassociated_eips = []
        self.associated_eips = []
        self.released_eips = []
        self.failed_releases = []

    def get_all_regions(self) -> List[str]:
        """
        Get list of all enabled AWS regions.

        Returns:
            List of region names
        """
        if self.specified_regions:
            return self.specified_regions

        try:
            ec2 = self.session.client('ec2')
            regions = ec2.describe_regions(
                Filters=[{'Name': 'opt-in-status', 'Values': ['opt-in-not-required', 'opted-in']}]
            )
            return [region['RegionName'] for region in regions['Regions']]
        except (ClientError, BotoCoreError) as e:
            print(f"Error retrieving regions: {e}", file=sys.stderr)
            print("Falling back to default region only", file=sys.stderr)
            return [self.session.region_name or 'us-east-1']

    def get_elastic_ips(self, region: str) -> List[Dict[str, Any]]:
        """
        Get all Elastic IP addresses in a specific region.

        Args:
            region: AWS region name

        Returns:
            List of Elastic IP address dictionaries
        """
        try:
            ec2 = self.session.client('ec2', region_name=region)
            response = ec2.describe_addresses()
            return response.get('Addresses', [])
        except (ClientError, BotoCoreError) as e:
            print(f"Error listing Elastic IPs in {region}: {e}", file=sys.stderr)
            return []

    def is_eip_unassociated(self, eip: Dict[str, Any]) -> bool:
        """
        Check if an Elastic IP is not associated with any resource.

        Args:
            eip: Elastic IP address dictionary

        Returns:
            True if EIP is not associated, False otherwise
        """
        # An EIP is considered unassociated if it has no AssociationId
        # and no InstanceId or NetworkInterfaceId
        return (
            'AssociationId' not in eip and
            'InstanceId' not in eip and
            'NetworkInterfaceId' not in eip
        )

    def get_eip_monthly_cost(self, eip_count: int) -> float:
        """
        Calculate monthly cost for unassociated Elastic IPs.

        Args:
            eip_count: Number of Elastic IPs

        Returns:
            Monthly cost in USD
        """
        # AWS charges for unassociated Elastic IPs
        # Approximate cost: $0.005 per hour = ~$3.60 per month
        return eip_count * 3.60

    def release_elastic_ip(self, eip: Dict[str, Any], region: str) -> bool:
        """
        Release an Elastic IP address.

        Args:
            eip: Elastic IP address dictionary
            region: AWS region name

        Returns:
            True if successful, False otherwise
        """
        allocation_id = eip.get('AllocationId')
        public_ip = eip.get('PublicIp', 'Unknown')

        if self.dry_run:
            print(f"  [DRY RUN] Would release EIP: {public_ip} ({allocation_id}) in {region}")
            return True

        try:
            ec2 = self.session.client('ec2', region_name=region)

            # Use AllocationId for VPC EIPs, PublicIp for EC2-Classic
            if allocation_id:
                ec2.release_address(AllocationId=allocation_id)
            else:
                ec2.release_address(PublicIp=public_ip)

            print(f"  ✓ Released EIP: {public_ip} ({allocation_id or 'EC2-Classic'}) in {region}")
            return True
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_msg = e.response.get('Error', {}).get('Message', str(e))
            print(f"  ✗ Failed to release EIP {public_ip} in {region}: {error_code} - {error_msg}", file=sys.stderr)
            return False
        except BotoCoreError as e:
            print(f"  ✗ Failed to release EIP {public_ip} in {region}: {e}", file=sys.stderr)
            return False

    def scan_elastic_ips(self) -> None:
        """Scan all regions for Elastic IPs and categorize them."""
        print("Scanning for Elastic IP addresses across all regions...")
        regions = self.get_all_regions()

        print(f"Checking {len(regions)} region(s): {', '.join(regions)}\n")

        total_eips = 0
        for region in regions:
            print(f"Scanning region: {region}")
            eips = self.get_elastic_ips(region)

            if not eips:
                print(f"  No Elastic IPs found in {region}")
                continue

            region_unassociated = 0
            region_associated = 0

            for eip in eips:
                total_eips += 1
                public_ip = eip.get('PublicIp', 'Unknown')
                allocation_id = eip.get('AllocationId', 'N/A')
                instance_id = eip.get('InstanceId', None)
                network_interface_id = eip.get('NetworkInterfaceId', None)
                domain = eip.get('Domain', 'standard')
                tags = {tag['Key']: tag['Value'] for tag in eip.get('Tags', [])}
                name = tags.get('Name', '')

                eip_info = {
                    'public_ip': public_ip,
                    'allocation_id': allocation_id,
                    'region': region,
                    'instance_id': instance_id,
                    'network_interface_id': network_interface_id,
                    'domain': domain,
                    'name': name,
                    'tags': tags
                }

                if self.is_eip_unassociated(eip):
                    region_unassociated += 1
                    name_str = f" ({name})" if name else ""
                    print(f"  → Unassociated: {public_ip}{name_str}")
                    self.unassociated_eips.append(eip_info)
                else:
                    region_associated += 1
                    attached_to = instance_id or network_interface_id or 'Unknown'
                    name_str = f" ({name})" if name else ""
                    print(f"  → Associated: {public_ip}{name_str} -> {attached_to}")
                    self.associated_eips.append(eip_info)

            print(f"  Found {len(eips)} EIP(s): {region_associated} associated, {region_unassociated} unassociated")

        print()
        print(f"Total Elastic IPs found: {total_eips}")

    def cleanup_unassociated_eips(self, skip_confirmation: bool = False) -> None:
        """
        Release unassociated Elastic IP addresses.

        Args:
            skip_confirmation: If True, skip confirmation prompt
        """
        if not self.unassociated_eips:
            print("No unassociated Elastic IPs to clean up.")
            return

        print(f"Found {len(self.unassociated_eips)} unassociated Elastic IP(s)")
        print()

        if not self.dry_run and not skip_confirmation:
            print("The following Elastic IPs will be RELEASED:")
            for eip in self.unassociated_eips:
                name_str = f" ({eip['name']})" if eip['name'] else ""
                print(f"  - {eip['public_ip']}{name_str} in {eip['region']}")
            print()

            response = input("Are you sure you want to release these Elastic IPs? (yes/no): ").strip().lower()
            if response not in ['yes', 'y']:
                print("Release cancelled.")
                return
            print()

        print("Processing Elastic IP releases...")
        for eip in self.unassociated_eips:
            # Reconstruct the eip dict format expected by release_elastic_ip
            eip_obj = {
                'PublicIp': eip['public_ip'],
                'AllocationId': eip['allocation_id'] if eip['allocation_id'] != 'N/A' else None
            }
            success = self.release_elastic_ip(eip_obj, eip['region'])
            if success:
                self.released_eips.append(eip)
            else:
                self.failed_releases.append(eip)

    def export_to_csv(self, filename: str) -> None:
        """
        Export findings to CSV file.

        Args:
            filename: Output CSV filename
        """
        try:
            with open(filename, 'w') as f:
                f.write("Public IP,Allocation ID,Region,Status,Attached To,Name,Tags\n")

                for eip in self.unassociated_eips:
                    status = "Released" if eip in self.released_eips else "Unassociated"
                    tags_str = ';'.join([f"{k}={v}" for k, v in eip['tags'].items()])
                    f.write(f'{eip["public_ip"]},{eip["allocation_id"]},{eip["region"]},{status},,"{eip["name"]}","{tags_str}"\n')

                for eip in self.associated_eips:
                    attached_to = eip['instance_id'] or eip['network_interface_id'] or ''
                    tags_str = ';'.join([f"{k}={v}" for k, v in eip['tags'].items()])
                    f.write(f'{eip["public_ip"]},{eip["allocation_id"]},{eip["region"]},Associated,{attached_to},"{eip["name"]}","{tags_str}"\n')

            print(f"CSV report saved to: {filename}")
        except IOError as e:
            print(f"Error writing CSV file: {e}", file=sys.stderr)

    def export_to_json(self, filename: str) -> None:
        """
        Export findings to JSON file.

        Args:
            filename: Output JSON filename
        """
        data = {
            'metadata': {
                'generated_at': datetime.utcnow().isoformat() + 'Z',
                'dry_run': self.dry_run,
                'total_eips': len(self.unassociated_eips) + len(self.associated_eips),
                'unassociated_eips': len(self.unassociated_eips),
                'associated_eips': len(self.associated_eips),
                'released_eips': len(self.released_eips),
                'failed_releases': len(self.failed_releases),
                'potential_monthly_savings_usd': self.get_eip_monthly_cost(len(self.released_eips))
            },
            'unassociated_eips': self.unassociated_eips,
            'associated_eips': self.associated_eips,
            'released_eips': [eip['public_ip'] for eip in self.released_eips],
            'failed_releases': [eip['public_ip'] for eip in self.failed_releases]
        }

        try:
            with open(filename, 'w') as f:
                json.dump(data, f, indent=2)
            print(f"JSON report saved to: {filename}")
        except IOError as e:
            print(f"Error writing JSON file: {e}", file=sys.stderr)

    def print_summary(self) -> None:
        """Print summary of findings and actions taken."""
        print()
        print("=" * 60)
        print("SUMMARY")
        print("=" * 60)
        print(f"Total Elastic IPs:         {len(self.unassociated_eips) + len(self.associated_eips)}")
        print(f"Unassociated IPs:          {len(self.unassociated_eips)}")
        print(f"Associated IPs:            {len(self.associated_eips)}")
        print()

        if self.released_eips:
            print(f"IPs released:              {len(self.released_eips)}")
            print(f"Monthly savings:           ${self.get_eip_monthly_cost(len(self.released_eips)):.2f}")

        if self.failed_releases:
            print(f"Failed releases:           {len(self.failed_releases)}")

        if self.unassociated_eips and not self.released_eips:
            potential_savings = self.get_eip_monthly_cost(len(self.unassociated_eips))
            print(f"Potential monthly savings: ${potential_savings:.2f}")
            print()
            print("Unassociated Elastic IPs found:")
            for eip in self.unassociated_eips:
                name_str = f" ({eip['name']})" if eip['name'] else ""
                print(f"  - {eip['public_ip']}{name_str} in {eip['region']}")

        if self.dry_run and self.unassociated_eips:
            print()
            print("This was a DRY RUN - no Elastic IPs were released.")
            print("Run without --dry-run to actually release the IPs.")

        print("=" * 60)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description='Identify and release unassociated Elastic IP addresses across all AWS regions',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run - identify unassociated EIPs without releasing
  %(prog)s --dry-run

  # Release unassociated EIPs with confirmation prompt
  %(prog)s --delete

  # Release unassociated EIPs without confirmation (use with caution!)
  %(prog)s --delete --force

  # Scan only and export to CSV
  %(prog)s --dry-run --output-csv unassociated-eips.csv

  # Use specific AWS profile
  %(prog)s --profile production --dry-run

  # Check specific regions only
  %(prog)s --regions us-east-1 us-west-2 --dry-run

  # Delete and export results
  %(prog)s --delete --force --output-csv released-eips.csv --output-json released-eips.json
        """
    )

    parser.add_argument(
        '--profile',
        help='AWS profile name to use (default: default profile)',
        default=None
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        default=False,
        help='Identify unassociated EIPs without releasing them (default behavior if --delete not specified)'
    )

    parser.add_argument(
        '--delete',
        action='store_true',
        default=False,
        help='Release unassociated Elastic IPs (with confirmation prompt)'
    )

    parser.add_argument(
        '--force',
        action='store_true',
        default=False,
        help='Skip confirmation prompt when releasing (use with --delete)'
    )

    parser.add_argument(
        '--regions',
        nargs='+',
        help='Specific regions to check (default: all enabled regions)',
        metavar='REGION'
    )

    parser.add_argument(
        '--output-csv',
        help='Export results to CSV file',
        metavar='FILE'
    )

    parser.add_argument(
        '--output-json',
        help='Export results to JSON file',
        metavar='FILE'
    )

    args = parser.parse_args()

    # Determine dry run mode
    dry_run = not args.delete or args.dry_run

    # Print header
    print("=" * 60)
    print("Elastic IP Cleanup")
    print("=" * 60)
    print()

    if dry_run:
        print("Mode: DRY RUN (identification only)")
    else:
        print("Mode: DELETE" + (" (forced)" if args.force else " (with confirmation)"))

    if args.profile:
        print(f"AWS Profile: {args.profile}")

    if args.regions:
        print(f"Regions: {', '.join(args.regions)}")
    else:
        print("Regions: All enabled regions")

    print()

    # Initialize cleanup tool
    cleanup = ElasticIPCleanup(profile=args.profile, dry_run=dry_run, regions=args.regions)

    # Scan all Elastic IPs
    cleanup.scan_elastic_ips()

    # Print initial findings
    print(f"Unassociated EIPs found: {len(cleanup.unassociated_eips)}")
    print(f"Associated EIPs found: {len(cleanup.associated_eips)}")

    if cleanup.unassociated_eips:
        potential_savings = cleanup.get_eip_monthly_cost(len(cleanup.unassociated_eips))
        print(f"Potential monthly savings: ${potential_savings:.2f}")

    print()

    # Release EIPs if requested
    if args.delete and cleanup.unassociated_eips:
        cleanup.cleanup_unassociated_eips(skip_confirmation=args.force)

    # Export to CSV if requested
    if args.output_csv:
        cleanup.export_to_csv(args.output_csv)

    # Export to JSON if requested
    if args.output_json:
        cleanup.export_to_json(args.output_json)

    # Print summary
    cleanup.print_summary()

    # Exit with appropriate code
    if cleanup.failed_releases:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
