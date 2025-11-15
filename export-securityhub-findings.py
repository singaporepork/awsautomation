#!/usr/bin/env python3
"""
AWS Security Hub Findings Exporter

This script exports AWS Security Hub findings from a single region to JSON format.
It supports filtering by various criteria and handles pagination automatically.

Requirements:
    - Python 3.6 or higher
    - boto3 library (pip install boto3)
    - AWS credentials configured (via AWS CLI, environment variables, or IAM role)

Author: AWS Security Automation
"""

import argparse
import json
import sys
from datetime import datetime
from typing import Dict, List, Optional, Any
import boto3
from botocore.exceptions import ClientError, NoCredentialsError


class SecurityHubExporter:
    """Export Security Hub findings to JSON format."""

    def __init__(self, region: str, profile: Optional[str] = None):
        """
        Initialize the Security Hub exporter.

        Args:
            region: AWS region name (e.g., 'us-east-1')
            profile: AWS CLI profile name (optional)
        """
        self.region = region
        self.profile = profile
        self.session = self._create_session()
        self.client = self.session.client('securityhub', region_name=region)
        self.findings = []

    def _create_session(self) -> boto3.Session:
        """Create and return a boto3 session."""
        if self.profile:
            return boto3.Session(profile_name=self.profile, region_name=self.region)
        return boto3.Session(region_name=self.region)

    def get_findings(
        self,
        severity: Optional[List[str]] = None,
        workflow_status: Optional[List[str]] = None,
        compliance_status: Optional[List[str]] = None,
        record_state: Optional[List[str]] = None,
        max_results: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Retrieve Security Hub findings with optional filters.

        Args:
            severity: List of severity levels (CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL)
            workflow_status: List of workflow statuses (NEW, NOTIFIED, RESOLVED, SUPPRESSED)
            compliance_status: List of compliance statuses (PASSED, WARNING, FAILED, NOT_AVAILABLE)
            record_state: List of record states (ACTIVE, ARCHIVED)
            max_results: Maximum number of findings to retrieve (None for all)

        Returns:
            List of findings as dictionaries
        """
        filters = self._build_filters(severity, workflow_status, compliance_status, record_state)

        print(f"Fetching Security Hub findings from {self.region}...")

        try:
            paginator = self.client.get_paginator('get_findings')
            page_iterator = paginator.paginate(
                Filters=filters,
                PaginationConfig={
                    'PageSize': 100,
                    'MaxItems': max_results
                }
            )

            finding_count = 0
            for page in page_iterator:
                findings = page.get('Findings', [])
                self.findings.extend(findings)
                finding_count += len(findings)
                print(f"Retrieved {finding_count} findings...", end='\r')

            print(f"\nTotal findings retrieved: {finding_count}")
            return self.findings

        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_msg = e.response['Error']['Message']

            if error_code == 'InvalidAccessException':
                print(f"Error: Security Hub is not enabled in {self.region}", file=sys.stderr)
            elif error_code == 'AccessDeniedException':
                print("Error: Insufficient permissions to access Security Hub", file=sys.stderr)
            else:
                print(f"Error: {error_code} - {error_msg}", file=sys.stderr)

            sys.exit(1)

        except NoCredentialsError:
            print("Error: AWS credentials not found", file=sys.stderr)
            print("Configure credentials using 'aws configure' or set environment variables", file=sys.stderr)
            sys.exit(1)

    def _build_filters(
        self,
        severity: Optional[List[str]] = None,
        workflow_status: Optional[List[str]] = None,
        compliance_status: Optional[List[str]] = None,
        record_state: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Build the filters dictionary for the Security Hub API."""
        filters = {}

        if severity:
            filters['SeverityLabel'] = [{'Value': s.upper(), 'Comparison': 'EQUALS'} for s in severity]

        if workflow_status:
            filters['WorkflowStatus'] = [{'Value': ws.upper(), 'Comparison': 'EQUALS'} for ws in workflow_status]

        if compliance_status:
            filters['ComplianceStatus'] = [{'Value': cs.upper(), 'Comparison': 'EQUALS'} for cs in compliance_status]

        if record_state:
            filters['RecordState'] = [{'Value': rs.upper(), 'Comparison': 'EQUALS'} for rs in record_state]

        return filters

    def export_to_json(self, output_file: str, pretty: bool = True) -> None:
        """
        Export findings to a JSON file.

        Args:
            output_file: Path to the output JSON file
            pretty: Whether to pretty-print the JSON (default: True)
        """
        if not self.findings:
            print("Warning: No findings to export", file=sys.stderr)
            return

        print(f"Exporting {len(self.findings)} findings to {output_file}...")

        # Create export metadata
        export_data = {
            'metadata': {
                'export_date': datetime.utcnow().isoformat() + 'Z',
                'region': self.region,
                'total_findings': len(self.findings),
                'severity_summary': self._get_severity_summary(),
                'workflow_summary': self._get_workflow_summary()
            },
            'findings': self.findings
        }

        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                if pretty:
                    json.dump(export_data, f, indent=2, default=str, ensure_ascii=False)
                else:
                    json.dump(export_data, f, default=str, ensure_ascii=False)

            print(f"Successfully exported findings to {output_file}")

        except IOError as e:
            print(f"Error writing to file: {e}", file=sys.stderr)
            sys.exit(1)

    def _get_severity_summary(self) -> Dict[str, int]:
        """Get a summary of findings by severity."""
        summary = {
            'CRITICAL': 0,
            'HIGH': 0,
            'MEDIUM': 0,
            'LOW': 0,
            'INFORMATIONAL': 0
        }

        for finding in self.findings:
            severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
            if severity in summary:
                summary[severity] += 1

        return summary

    def _get_workflow_summary(self) -> Dict[str, int]:
        """Get a summary of findings by workflow status."""
        summary = {
            'NEW': 0,
            'NOTIFIED': 0,
            'RESOLVED': 0,
            'SUPPRESSED': 0
        }

        for finding in self.findings:
            workflow = finding.get('Workflow', {}).get('Status', 'UNKNOWN')
            if workflow in summary:
                summary[workflow] += 1

        return summary

    def print_summary(self) -> None:
        """Print a summary of the findings."""
        if not self.findings:
            print("\nNo findings found.")
            return

        print("\n" + "=" * 60)
        print("FINDINGS SUMMARY")
        print("=" * 60)

        # Severity summary
        print("\nBy Severity:")
        severity_summary = self._get_severity_summary()
        for severity, count in severity_summary.items():
            if count > 0:
                print(f"  {severity:15} {count:6}")

        # Workflow summary
        print("\nBy Workflow Status:")
        workflow_summary = self._get_workflow_summary()
        for status, count in workflow_summary.items():
            if count > 0:
                print(f"  {status:15} {count:6}")

        # Top generators
        print("\nTop Finding Generators:")
        generators = {}
        for finding in self.findings:
            gen = finding.get('GeneratorId', 'Unknown')
            # Shorten long generator IDs
            if len(gen) > 50:
                gen = gen[:47] + '...'
            generators[gen] = generators.get(gen, 0) + 1

        for gen, count in sorted(generators.items(), key=lambda x: x[1], reverse=True)[:5]:
            print(f"  {count:4} - {gen}")

        print("\n" + "=" * 60)


def main():
    """Main function to parse arguments and export findings."""
    parser = argparse.ArgumentParser(
        description='Export AWS Security Hub findings to JSON format',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Export all findings from us-east-1
  %(prog)s --region us-east-1 --output findings.json

  # Export only CRITICAL and HIGH severity findings
  %(prog)s --region us-east-1 --severity CRITICAL HIGH --output critical-findings.json

  # Export only NEW findings
  %(prog)s --region us-west-2 --workflow-status NEW --output new-findings.json

  # Export only ACTIVE findings with specific compliance status
  %(prog)s --region us-east-1 --record-state ACTIVE --compliance-status FAILED

  # Use a specific AWS CLI profile
  %(prog)s --region us-east-1 --profile production --output findings.json

  # Limit to 100 findings
  %(prog)s --region us-east-1 --max-results 100 --output sample-findings.json
        """
    )

    parser.add_argument(
        '--region',
        required=True,
        help='AWS region (e.g., us-east-1, us-west-2)'
    )

    parser.add_argument(
        '--output',
        default='securityhub-findings.json',
        help='Output JSON file path (default: securityhub-findings.json)'
    )

    parser.add_argument(
        '--severity',
        nargs='+',
        choices=['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFORMATIONAL'],
        help='Filter by severity level(s)'
    )

    parser.add_argument(
        '--workflow-status',
        nargs='+',
        choices=['NEW', 'NOTIFIED', 'RESOLVED', 'SUPPRESSED'],
        help='Filter by workflow status(es)'
    )

    parser.add_argument(
        '--compliance-status',
        nargs='+',
        choices=['PASSED', 'WARNING', 'FAILED', 'NOT_AVAILABLE'],
        help='Filter by compliance status(es)'
    )

    parser.add_argument(
        '--record-state',
        nargs='+',
        choices=['ACTIVE', 'ARCHIVED'],
        help='Filter by record state (default: ACTIVE only)'
    )

    parser.add_argument(
        '--max-results',
        type=int,
        help='Maximum number of findings to retrieve (default: all)'
    )

    parser.add_argument(
        '--profile',
        help='AWS CLI profile name to use'
    )

    parser.add_argument(
        '--compact',
        action='store_true',
        help='Output compact JSON (no pretty-printing)'
    )

    parser.add_argument(
        '--summary-only',
        action='store_true',
        help='Print summary only, do not export to file'
    )

    args = parser.parse_args()

    # Create exporter
    exporter = SecurityHubExporter(region=args.region, profile=args.profile)

    # Get findings with filters
    exporter.get_findings(
        severity=args.severity,
        workflow_status=args.workflow_status,
        compliance_status=args.compliance_status,
        record_state=args.record_state,
        max_results=args.max_results
    )

    # Print summary
    exporter.print_summary()

    # Export to JSON unless summary-only
    if not args.summary_only:
        exporter.export_to_json(args.output, pretty=not args.compact)


if __name__ == '__main__':
    main()
