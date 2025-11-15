# AWS Security Hub Findings Exporter

Python script to export AWS Security Hub findings from a single region to JSON format with comprehensive filtering and metadata.

## Features

- **Complete findings export** with automatic pagination
- **Flexible filtering** by severity, workflow status, compliance status, and record state
- **Rich metadata** including export timestamp, region, and summary statistics
- **Summary report** showing findings breakdown by severity and workflow status
- **Multiple output formats** (pretty-printed or compact JSON)
- **AWS profile support** for multi-account access
- **Error handling** with helpful error messages

## Prerequisites

### Python Requirements

- **Python 3.6 or higher**
- **boto3 library**: AWS SDK for Python

Install boto3:
```bash
pip install boto3
```

Or using a requirements file:
```bash
pip install -r requirements.txt
```

### AWS Requirements

1. **AWS Security Hub enabled** in the target region
2. **AWS credentials configured** via one of:
   - AWS CLI: `aws configure`
   - Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
   - IAM role (if running on EC2, Lambda, etc.)

3. **Required IAM permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "securityhub:GetFindings",
        "securityhub:DescribeHub"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### Basic Usage

Export all findings from a region:
```bash
./export-securityhub-findings.py --region us-east-1 --output findings.json
```

### Filter by Severity

Export only CRITICAL and HIGH severity findings:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL HIGH \
  --output critical-findings.json
```

### Filter by Workflow Status

Export only NEW findings (not yet addressed):
```bash
./export-securityhub-findings.py \
  --region us-west-2 \
  --workflow-status NEW \
  --output new-findings.json
```

### Filter by Compliance Status

Export failed compliance checks:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --compliance-status FAILED \
  --output failed-compliance.json
```

### Multiple Filters

Combine multiple filters:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL HIGH \
  --workflow-status NEW NOTIFIED \
  --record-state ACTIVE \
  --output active-critical-findings.json
```

### Use AWS Profile

Export using a specific AWS CLI profile:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --profile production \
  --output findings.json
```

### Limit Results

Export only the first 100 findings:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --max-results 100 \
  --output sample-findings.json
```

### Summary Only

Print summary statistics without exporting:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --summary-only
```

### Compact JSON

Export without pretty-printing (smaller file size):
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --compact \
  --output findings.json
```

## Command-Line Options

| Option | Description | Values |
|--------|-------------|--------|
| `--region` | AWS region (required) | us-east-1, us-west-2, etc. |
| `--output` | Output file path | Default: securityhub-findings.json |
| `--severity` | Filter by severity | CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL |
| `--workflow-status` | Filter by workflow status | NEW, NOTIFIED, RESOLVED, SUPPRESSED |
| `--compliance-status` | Filter by compliance | PASSED, WARNING, FAILED, NOT_AVAILABLE |
| `--record-state` | Filter by record state | ACTIVE, ARCHIVED |
| `--max-results` | Limit number of findings | Any positive integer |
| `--profile` | AWS CLI profile name | Profile from ~/.aws/credentials |
| `--compact` | Compact JSON output | Flag (no value) |
| `--summary-only` | Print summary only | Flag (no value) |

## Output Format

The script exports findings in the following JSON structure:

```json
{
  "metadata": {
    "export_date": "2024-01-15T10:30:45Z",
    "region": "us-east-1",
    "total_findings": 156,
    "severity_summary": {
      "CRITICAL": 5,
      "HIGH": 23,
      "MEDIUM": 67,
      "LOW": 45,
      "INFORMATIONAL": 16
    },
    "workflow_summary": {
      "NEW": 89,
      "NOTIFIED": 34,
      "RESOLVED": 28,
      "SUPPRESSED": 5
    }
  },
  "findings": [
    {
      "SchemaVersion": "2018-10-08",
      "Id": "arn:aws:securityhub:us-east-1:123456789012:...",
      "ProductArn": "arn:aws:securityhub:us-east-1::product/aws/securityhub",
      "GeneratorId": "aws-foundational-security-best-practices/v/1.0.0/EC2.1",
      "AwsAccountId": "123456789012",
      "Types": ["Software and Configuration Checks/AWS Security Best Practices"],
      "CreatedAt": "2024-01-10T08:00:00.000Z",
      "UpdatedAt": "2024-01-15T10:00:00.000Z",
      "Severity": {
        "Label": "MEDIUM",
        "Normalized": 40
      },
      "Title": "EC2 instances should be managed by Systems Manager",
      "Description": "This control checks whether EC2 instances are managed by AWS Systems Manager.",
      "Remediation": {
        "Recommendation": {
          "Text": "Enable Systems Manager...",
          "Url": "https://docs.aws.amazon.com/..."
        }
      },
      "ProductFields": { ... },
      "Resources": [ ... ],
      "Compliance": {
        "Status": "FAILED"
      },
      "Workflow": {
        "Status": "NEW"
      },
      "RecordState": "ACTIVE"
    }
  ]
}
```

## Summary Output

When the script runs, it prints a summary to the console:

```
Fetching Security Hub findings from us-east-1...
Retrieved 156 findings...

Total findings retrieved: 156

============================================================
FINDINGS SUMMARY
============================================================

By Severity:
  CRITICAL            5
  HIGH               23
  MEDIUM             67
  LOW                45
  INFORMATIONAL      16

By Workflow Status:
  NEW                89
  NOTIFIED           34
  RESOLVED           28
  SUPPRESSED          5

Top Finding Generators:
    45 - aws-foundational-security-best-practices/v/1.0.0
    34 - cis-aws-foundations-benchmark/v/1.2.0
    28 - guardduty
    25 - arn:aws:securityhub:::ruleset/cis-aws-foun...
    24 - aws-foundational-security-best-practices/v/...

============================================================

Exporting 156 findings to findings.json...
Successfully exported findings to findings.json
```

## Use Cases

### 1. Security Reporting

Export findings for monthly security reports:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --output "security-report-$(date +%Y-%m).json"
```

### 2. Critical Findings Escalation

Export critical findings for immediate review:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL \
  --workflow-status NEW \
  --output critical-new-findings.json
```

### 3. Compliance Audit

Export all failed compliance checks:
```bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --compliance-status FAILED \
  --output compliance-failures.json
```

### 4. Multi-Region Export

Export findings from multiple regions:
```bash
for region in us-east-1 us-west-2 eu-west-1; do
  ./export-securityhub-findings.py \
    --region $region \
    --output "findings-${region}.json"
done
```

### 5. Integration with Other Tools

Export for processing with jq:
```bash
./export-securityhub-findings.py --region us-east-1 --compact --output findings.json

# Extract only CRITICAL findings
cat findings.json | jq '.findings[] | select(.Severity.Label == "CRITICAL")'

# Count findings by severity
cat findings.json | jq '.metadata.severity_summary'

# Get unique resource types affected
cat findings.json | jq '.findings[].Resources[].Type' | sort -u
```

### 6. Scheduled Export (Cron)

Add to crontab for daily exports:
```cron
# Export Security Hub findings daily at 2 AM
0 2 * * * /path/to/export-securityhub-findings.py \
  --region us-east-1 \
  --output /var/reports/securityhub-$(date +\%Y\%m\%d).json
```

## Error Handling

The script provides clear error messages for common issues:

### Security Hub Not Enabled
```
Error: Security Hub is not enabled in us-east-1
```

**Solution**: Enable Security Hub in the region:
```bash
aws securityhub enable-security-hub --region us-east-1
```

### Insufficient Permissions
```
Error: Insufficient permissions to access Security Hub
```

**Solution**: Add the required IAM permissions (see Prerequisites section)

### AWS Credentials Not Found
```
Error: AWS credentials not found
Configure credentials using 'aws configure' or set environment variables
```

**Solution**: Configure AWS credentials:
```bash
aws configure
```

## Performance Considerations

- **Pagination**: The script automatically handles pagination, retrieving 100 findings per API call
- **Large exports**: For accounts with thousands of findings, the export may take several minutes
- **Rate limits**: AWS Security Hub API has rate limits; the script respects these automatically
- **Memory usage**: All findings are held in memory before export; for very large result sets (>10,000 findings), consider using filters

## Integration Examples

### Python Integration

Use the exporter class in your own Python code:

```python
from export_securityhub_findings import SecurityHubExporter

# Create exporter
exporter = SecurityHubExporter(region='us-east-1')

# Get findings
findings = exporter.get_findings(
    severity=['CRITICAL', 'HIGH'],
    workflow_status=['NEW']
)

# Process findings
for finding in findings:
    print(f"{finding['Severity']['Label']}: {finding['Title']}")

# Export to JSON
exporter.export_to_json('findings.json')
```

### CI/CD Pipeline

Use in a CI/CD pipeline to fail builds on critical findings:

```bash
#!/bin/bash
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL \
  --workflow-status NEW \
  --output critical.json

CRITICAL_COUNT=$(cat critical.json | jq '.metadata.severity_summary.CRITICAL')

if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "ERROR: $CRITICAL_COUNT critical findings found!"
  exit 1
fi

echo "No critical findings, proceeding with deployment"
```

### Lambda Function

Deploy as an AWS Lambda function for scheduled exports to S3:

```python
import json
import boto3
from export_securityhub_findings import SecurityHubExporter

def lambda_handler(event, context):
    region = event.get('region', 'us-east-1')
    bucket = event.get('bucket', 'security-reports')

    # Export findings
    exporter = SecurityHubExporter(region=region)
    exporter.get_findings()

    # Upload to S3
    s3 = boto3.client('s3')
    filename = f'securityhub-{region}-{datetime.now().strftime("%Y%m%d")}.json'

    export_data = {
        'metadata': {...},
        'findings': exporter.findings
    }

    s3.put_object(
        Bucket=bucket,
        Key=filename,
        Body=json.dumps(export_data, default=str)
    )

    return {
        'statusCode': 200,
        'body': json.dumps(f'Exported {len(exporter.findings)} findings')
    }
```

## Troubleshooting

### No findings returned

If the script returns 0 findings but you expect results:

1. Verify Security Hub is enabled: `aws securityhub describe-hub --region us-east-1`
2. Check if findings exist in the console
3. Try removing filters: run without `--severity`, `--workflow-status`, etc.
4. Verify the correct region is specified

### Module not found: boto3

Install the boto3 library:
```bash
pip install boto3
```

Or using a virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install boto3
```

### Permission denied when executing

Make the script executable:
```bash
chmod +x export-securityhub-findings.py
```

## Best Practices

1. **Use filters**: When exporting regularly, use filters to reduce data volume
2. **Regular exports**: Schedule regular exports for trend analysis
3. **Archive findings**: Export and archive resolved findings periodically
4. **Secure storage**: Store exported findings securely (encrypt, restrict access)
5. **Multi-region**: Export from all active regions for complete coverage
6. **Version control**: Keep historical exports for compliance and auditing

## License

This project is provided as-is for AWS security automation purposes.
