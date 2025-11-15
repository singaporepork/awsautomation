#!/usr/bin/env python3
"""
Route 53 Empty Hosted Zones Cleanup Script

Identifies and optionally deletes Route 53 hosted zones that only contain
default NS (Name Server) and SOA (Start of Authority) records. These are
often leftover from testing or decommissioned applications.

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


class Route53ZoneCleanup:
    """Main class for Route 53 hosted zone cleanup operations."""

    def __init__(self, profile: Optional[str] = None, dry_run: bool = True):
        """
        Initialize the Route 53 cleanup tool.

        Args:
            profile: AWS profile name to use
            dry_run: If True, only report what would be deleted without actually deleting
        """
        self.session = boto3.Session(profile_name=profile) if profile else boto3.Session()
        self.route53 = self.session.client('route53')
        self.dry_run = dry_run
        self.empty_zones = []
        self.non_empty_zones = []
        self.deleted_zones = []
        self.failed_deletes = []

    def list_hosted_zones(self) -> List[Dict[str, Any]]:
        """
        List all Route 53 hosted zones with pagination support.

        Returns:
            List of hosted zone dictionaries
        """
        zones = []
        paginator = self.route53.get_paginator('list_hosted_zones')

        try:
            for page in paginator.paginate():
                zones.extend(page.get('HostedZones', []))
        except (ClientError, BotoCoreError) as e:
            print(f"Error listing hosted zones: {e}", file=sys.stderr)
            sys.exit(1)

        return zones

    def get_record_sets(self, zone_id: str) -> List[Dict[str, Any]]:
        """
        Get all resource record sets for a hosted zone.

        Args:
            zone_id: The hosted zone ID

        Returns:
            List of resource record set dictionaries
        """
        record_sets = []
        paginator = self.route53.get_paginator('list_resource_record_sets')

        try:
            for page in paginator.paginate(HostedZoneId=zone_id):
                record_sets.extend(page.get('ResourceRecordSets', []))
        except (ClientError, BotoCoreError) as e:
            print(f"Error listing records for zone {zone_id}: {e}", file=sys.stderr)
            return []

        return record_sets

    def is_zone_empty(self, record_sets: List[Dict[str, Any]]) -> bool:
        """
        Check if a hosted zone only contains NS and SOA records.

        Args:
            record_sets: List of resource record sets

        Returns:
            True if zone only has NS and SOA records, False otherwise
        """
        for record in record_sets:
            record_type = record.get('Type', '')
            # Skip NS and SOA records as they are default
            if record_type not in ['NS', 'SOA']:
                return False
        return True

    def count_record_types(self, record_sets: List[Dict[str, Any]]) -> Dict[str, int]:
        """
        Count records by type.

        Args:
            record_sets: List of resource record sets

        Returns:
            Dictionary mapping record type to count
        """
        counts = {}
        for record in record_sets:
            record_type = record.get('Type', 'UNKNOWN')
            counts[record_type] = counts.get(record_type, 0) + 1
        return counts

    def get_zone_cost(self, zone_count: int) -> float:
        """
        Calculate monthly cost for hosted zones.

        Args:
            zone_count: Number of hosted zones

        Returns:
            Monthly cost in USD
        """
        # Route 53 pricing: $0.50 per hosted zone per month
        return zone_count * 0.50

    def delete_hosted_zone(self, zone_id: str, zone_name: str) -> bool:
        """
        Delete a hosted zone.

        Args:
            zone_id: The hosted zone ID
            zone_name: The hosted zone name (for logging)

        Returns:
            True if successful, False otherwise
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would delete zone: {zone_name} ({zone_id})")
            return True

        try:
            self.route53.delete_hosted_zone(Id=zone_id)
            print(f"  ✓ Deleted zone: {zone_name} ({zone_id})")
            return True
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_msg = e.response.get('Error', {}).get('Message', str(e))
            print(f"  ✗ Failed to delete zone {zone_name}: {error_code} - {error_msg}", file=sys.stderr)
            return False
        except BotoCoreError as e:
            print(f"  ✗ Failed to delete zone {zone_name}: {e}", file=sys.stderr)
            return False

    def scan_zones(self) -> None:
        """Scan all hosted zones and categorize them as empty or non-empty."""
        print("Scanning Route 53 hosted zones...")
        zones = self.list_hosted_zones()
        total_zones = len(zones)

        if total_zones == 0:
            print("No hosted zones found in this account.")
            return

        print(f"Found {total_zones} hosted zone(s) to analyze\n")

        for i, zone in enumerate(zones, 1):
            zone_id = zone['Id']
            zone_name = zone['Name']
            is_private = zone.get('Config', {}).get('PrivateZone', False)

            print(f"[{i}/{total_zones}] Checking zone: {zone_name} ({'Private' if is_private else 'Public'})")

            # Get all records for this zone
            record_sets = self.get_record_sets(zone_id)
            record_counts = self.count_record_types(record_sets)
            total_records = len(record_sets)

            zone_info = {
                'zone_id': zone_id,
                'zone_name': zone_name,
                'is_private': is_private,
                'total_records': total_records,
                'record_counts': record_counts,
                'resource_record_count': zone.get('ResourceRecordSetCount', 0)
            }

            # Check if zone is empty (only NS and SOA)
            if self.is_zone_empty(record_sets):
                print(f"  → Empty zone (only NS and SOA records)")
                self.empty_zones.append(zone_info)
            else:
                print(f"  → Active zone ({total_records} record(s): {', '.join([f'{k}={v}' for k, v in record_counts.items()])})")
                self.non_empty_zones.append(zone_info)

        print()

    def cleanup_empty_zones(self, skip_confirmation: bool = False) -> None:
        """
        Delete empty hosted zones.

        Args:
            skip_confirmation: If True, skip confirmation prompt
        """
        if not self.empty_zones:
            print("No empty zones to clean up.")
            return

        print(f"Found {len(self.empty_zones)} empty hosted zone(s)")
        print()

        if not self.dry_run and not skip_confirmation:
            print("The following zones will be DELETED:")
            for zone in self.empty_zones:
                zone_type = "Private" if zone['is_private'] else "Public"
                print(f"  - {zone['zone_name']} ({zone_type})")
            print()

            response = input("Are you sure you want to delete these zones? (yes/no): ").strip().lower()
            if response not in ['yes', 'y']:
                print("Deletion cancelled.")
                return
            print()

        print("Processing zone deletions...")
        for zone in self.empty_zones:
            success = self.delete_hosted_zone(zone['zone_id'], zone['zone_name'])
            if success:
                self.deleted_zones.append(zone)
            else:
                self.failed_deletes.append(zone)

    def export_to_csv(self, filename: str) -> None:
        """
        Export findings to CSV file.

        Args:
            filename: Output CSV filename
        """
        try:
            with open(filename, 'w') as f:
                f.write("Zone Name,Zone ID,Type,Total Records,Record Types,Status\n")

                for zone in self.empty_zones:
                    zone_type = "Private" if zone['is_private'] else "Public"
                    record_types = ','.join([f"{k}:{v}" for k, v in zone['record_counts'].items()])
                    status = "Deleted" if zone in self.deleted_zones else "Empty"
                    f.write(f'"{zone["zone_name"]}",{zone["zone_id"]},{zone_type},{zone["total_records"]},"{record_types}",{status}\n')

                for zone in self.non_empty_zones:
                    zone_type = "Private" if zone['is_private'] else "Public"
                    record_types = ','.join([f"{k}:{v}" for k, v in zone['record_counts'].items()])
                    f.write(f'"{zone["zone_name"]}",{zone["zone_id"]},{zone_type},{zone["total_records"]},"{record_types}",Active\n')

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
                'total_zones': len(self.empty_zones) + len(self.non_empty_zones),
                'empty_zones': len(self.empty_zones),
                'non_empty_zones': len(self.non_empty_zones),
                'deleted_zones': len(self.deleted_zones),
                'failed_deletes': len(self.failed_deletes),
                'potential_monthly_savings_usd': self.get_zone_cost(len(self.deleted_zones))
            },
            'empty_zones': self.empty_zones,
            'non_empty_zones': self.non_empty_zones,
            'deleted_zones': [z['zone_id'] for z in self.deleted_zones],
            'failed_deletes': [z['zone_id'] for z in self.failed_deletes]
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
        print(f"Total hosted zones:        {len(self.empty_zones) + len(self.non_empty_zones)}")
        print(f"Empty zones (NS/SOA only): {len(self.empty_zones)}")
        print(f"Active zones:              {len(self.non_empty_zones)}")
        print()

        if self.deleted_zones:
            print(f"Zones deleted:             {len(self.deleted_zones)}")
            print(f"Monthly savings:           ${self.get_zone_cost(len(self.deleted_zones)):.2f}")

        if self.failed_deletes:
            print(f"Failed deletions:          {len(self.failed_deletes)}")

        if self.empty_zones and not self.deleted_zones:
            potential_savings = self.get_zone_cost(len(self.empty_zones))
            print(f"Potential monthly savings: ${potential_savings:.2f}")
            print()
            print("Empty zones found:")
            for zone in self.empty_zones:
                zone_type = "Private" if zone['is_private'] else "Public"
                print(f"  - {zone['zone_name']} ({zone_type})")

        if self.dry_run and self.empty_zones:
            print()
            print("This was a DRY RUN - no zones were deleted.")
            print("Run without --dry-run to actually delete the zones.")

        print("=" * 60)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description='Identify and delete Route 53 hosted zones with only NS and SOA records',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run - identify empty zones without deleting
  %(prog)s --dry-run

  # Delete empty zones with confirmation prompt
  %(prog)s --delete

  # Delete empty zones without confirmation (use with caution!)
  %(prog)s --delete --force

  # Scan only and export to CSV
  %(prog)s --dry-run --output-csv empty-zones.csv

  # Use specific AWS profile
  %(prog)s --profile production --dry-run

  # Delete and export results
  %(prog)s --delete --force --output-csv deleted-zones.csv --output-json deleted-zones.json
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
        help='Identify empty zones without deleting them (default behavior if --delete not specified)'
    )

    parser.add_argument(
        '--delete',
        action='store_true',
        default=False,
        help='Delete empty hosted zones (with confirmation prompt)'
    )

    parser.add_argument(
        '--force',
        action='store_true',
        default=False,
        help='Skip confirmation prompt when deleting (use with --delete)'
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
    print("Route 53 Empty Hosted Zones Cleanup")
    print("=" * 60)
    print()

    if dry_run:
        print("Mode: DRY RUN (identification only)")
    else:
        print("Mode: DELETE" + (" (forced)" if args.force else " (with confirmation)"))

    if args.profile:
        print(f"AWS Profile: {args.profile}")

    print()

    # Initialize cleanup tool
    cleanup = Route53ZoneCleanup(profile=args.profile, dry_run=dry_run)

    # Scan all zones
    cleanup.scan_zones()

    # Print initial findings
    print(f"Empty zones found: {len(cleanup.empty_zones)}")
    print(f"Active zones found: {len(cleanup.non_empty_zones)}")

    if cleanup.empty_zones:
        potential_savings = cleanup.get_zone_cost(len(cleanup.empty_zones))
        print(f"Potential monthly savings: ${potential_savings:.2f}")

    print()

    # Delete zones if requested
    if args.delete and cleanup.empty_zones:
        cleanup.cleanup_empty_zones(skip_confirmation=args.force)

    # Export to CSV if requested
    if args.output_csv:
        cleanup.export_to_csv(args.output_csv)

    # Export to JSON if requested
    if args.output_json:
        cleanup.export_to_json(args.output_json)

    # Print summary
    cleanup.print_summary()

    # Exit with appropriate code
    if cleanup.failed_deletes:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
