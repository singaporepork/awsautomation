# AWS Security Automation

This repository contains tools and Infrastructure as Code (IaC) for AWS security automation, compliance monitoring, and security service deployment.

## Contents

- **[IAM Audit Scripts](#iam-audit-scripts)**: Bash and PowerShell scripts for auditing IAM security configurations
- **[Python Scripts](#python-scripts)**: Python tools for exporting and analyzing security data
- **[Terraform Modules](#terraform-modules)**: Infrastructure as Code for deploying AWS security services

---

## Terraform Modules

### Security Services Deployment

**Location**: `terraform/`

Terraform module to enable and configure AWS security services across multiple regions:

- **AWS Config**: Configuration recording and compliance monitoring
- **AWS GuardDuty**: Threat detection and continuous security monitoring
- **AWS Security Hub**: Centralized security findings aggregation

**Regions**: us-east-1 and us-west-2

**Quick Start**:
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

See the [Terraform README](terraform/README.md) for complete documentation.

---

## Python Scripts

### Security Hub Findings Exporter

**File**: `export-securityhub-findings.py`

Python script to export AWS Security Hub findings from a single region to JSON format with comprehensive filtering and metadata.

**Features**:
- Complete findings export with automatic pagination
- Filter by severity, workflow status, compliance status, and record state
- Rich metadata including export timestamp and summary statistics
- Summary report with findings breakdown
- AWS profile support for multi-account access

**Prerequisites**:
- Python 3.6 or higher
- boto3 library: `pip install -r requirements.txt`
- AWS credentials configured
- Security Hub enabled in target region

**Quick Start**:
```bash
# Install dependencies
pip install -r requirements.txt

# Export all findings
./export-securityhub-findings.py --region us-east-1 --output findings.json

# Export only CRITICAL findings
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL \
  --output critical-findings.json

# View summary only
./export-securityhub-findings.py --region us-east-1 --summary-only
```

**Common Use Cases**:
```bash
# Export NEW critical/high findings for immediate review
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL HIGH \
  --workflow-status NEW \
  --output new-critical.json

# Export failed compliance checks
./export-securityhub-findings.py \
  --region us-east-1 \
  --compliance-status FAILED \
  --output compliance-failures.json

# Multi-region export
for region in us-east-1 us-west-2; do
  ./export-securityhub-findings.py \
    --region $region \
    --output findings-${region}.json
done
```

See [SECURITY-HUB-EXPORT.md](SECURITY-HUB-EXPORT.md) for complete documentation, including advanced filtering, integration examples, and troubleshooting.

---

## IAM Audit Scripts

Security audit scripts for AWS IAM to help identify potential security issues and maintain compliance with AWS best practices.

### Available Scripts

### IAM Password Policy Audit
Identifies IAM users who do not have the "IAMUserChangePassword" policy attached.
- `audit-iam-password-policy.sh` - Bash script for Linux/macOS
- `audit-iam-password-policy.ps1` - PowerShell script for Windows

### Old Access Keys Audit
Identifies IAM users with access keys older than 365 days.
- `audit-old-access-keys.sh` - Bash script for Linux/macOS
- `audit-old-access-keys.ps1` - PowerShell script for Windows

### MFA Enabled Audit
Identifies IAM users who do not have Multi-Factor Authentication (MFA) enabled.
- `audit-mfa-enabled.sh` - Bash script for Linux/macOS
- `audit-mfa-enabled.ps1` - PowerShell script for Windows

---

# IAM Password Policy Audit

## Overview

These scripts audit all IAM users in your AWS account and identify those who lack the ability to change their own password. They check for the `iam:ChangePassword` permission through:

- **Direct policy attachments**: Managed and inline policies attached directly to the user
- **Group memberships**: Policies (both managed and inline) attached to groups the user belongs to

Both scripts provide identical functionality and output format, allowing you to use the appropriate version for your operating system.

---

## Bash Script (Linux/macOS)

### File: `audit-iam-password-policy.sh`

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **jq**: JSON processor (required for parsing policy documents)
   ```bash
   # Install on Ubuntu/Debian
   sudo apt-get install jq

   # Install on macOS
   brew install jq

   # Install on Amazon Linux/RHEL/CentOS
   sudo yum install jq
   ```

3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```bash
chmod +x audit-iam-password-policy.sh
./audit-iam-password-policy.sh
```

---

## PowerShell Script (Windows)

### File: `audit-iam-password-policy.ps1`

### Prerequisites

1. **PowerShell 5.0 or later**: Included with Windows 10/11 and Windows Server 2016+
   - Check version: `$PSVersionTable.PSVersion`

2. **AWS CLI**: Must be installed and configured
   - Download from: https://aws.amazon.com/cli/
   - Install using MSI installer or via command line

3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```powershell
# Run from PowerShell console
.\audit-iam-password-policy.ps1

# If you encounter execution policy errors, you may need to allow script execution:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Required AWS Permissions

Both scripts require the following IAM permissions:

- `iam:ListUsers`
- `iam:ListAttachedUserPolicies`
- `iam:ListUserPolicies`
- `iam:GetUserPolicy`
- `iam:ListGroupsForUser`
- `iam:ListAttachedGroupPolicies`
- `iam:ListGroupPolicies`
- `iam:GetGroupPolicy`
- `iam:GetPolicy`
- `iam:GetPolicyVersion`

---

## Output

Both scripts provide:

1. **Console output**: Color-coded results showing which users have/don't have the permission
   - ✓ (Green) - User has change password permission
   - ✗ (Red) - User lacks change password permission

2. **Detailed report** (`iam_password_policy_audit_report.txt`): Comprehensive audit trail showing:
   - Each user checked
   - How they have (or don't have) the permission
   - Source of permissions (direct policy, group, etc.)

3. **Users list** (`users_without_change_password_policy.txt`): Simple list of usernames that lack the permission

## Example Output

```
==========================================
IAM Password Policy Audit
==========================================

Fetching IAM users...
Found 5 IAM users

✓ admin-user - Has change password permission
✗ service-account - Missing change password permission
✓ developer1 - Has change password permission
✗ readonly-user - Missing change password permission
✓ developer2 - Has change password permission

==========================================
Summary
==========================================
Total users: 5
Users with change password permission: 3
Users without change password permission: 2

Users without IAMUserChangePassword policy:
service-account
readonly-user

Detailed report saved to: iam_password_policy_audit_report.txt
Users without policy saved to: users_without_change_password_policy.txt
```

---

# Old Access Keys Audit

## Overview

These scripts identify IAM users with access keys that are older than 365 days (configurable). Regular rotation of access keys is a critical security best practice to reduce the risk of compromised credentials.

**Key Features:**
- Identifies access keys older than a specified age (default: 365 days)
- Shows age in days for each access key
- Provides both detailed report and CSV export
- Color-coded console output for quick review

---

## Bash Script (Linux/macOS)

### File: `audit-old-access-keys.sh`

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```bash
chmod +x audit-old-access-keys.sh
./audit-old-access-keys.sh
```

---

## PowerShell Script (Windows)

### File: `audit-old-access-keys.ps1`

### Prerequisites

1. **PowerShell 5.0 or later**: Included with Windows 10/11 and Windows Server 2016+
2. **AWS CLI**: Must be installed and configured
3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```powershell
# Run with default 365 days threshold
.\audit-old-access-keys.ps1

# Run with custom threshold (e.g., 90 days)
.\audit-old-access-keys.ps1 -MaxAgeDays 90

# If you encounter execution policy errors:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Required AWS Permissions

Both scripts require the following IAM permissions:

- `iam:ListUsers`
- `iam:ListAccessKeys`

---

## Output

Both scripts provide:

1. **Console output**: Color-coded results showing access key status
   - ✓ (Green) - All keys within acceptable age
   - ✗ (Red) - Has one or more keys older than threshold
   - ○ (Blue) - No access keys

2. **Detailed report** (`old_access_keys_report.txt`): Comprehensive audit showing:
   - Each user and their access keys
   - Age in days for each key
   - Status (Active/Inactive)
   - Creation date

3. **CSV export** (`old_access_keys.csv`): Machine-readable format with columns:
   - UserName
   - AccessKeyId
   - Status
   - Age (Days)
   - Created Date

## Example Output

```
==========================================
IAM Access Keys Age Audit
==========================================
Checking for access keys older than 365 days

Fetching IAM users...
Found 5 IAM users

✓ developer1 - All access keys are within acceptable age
✗ service-account - Has access key(s) older than 365 days
○ admin-user - No access keys
✓ developer2 - All access keys are within acceptable age
✗ old-user - Has access key(s) older than 365 days

==========================================
Summary
==========================================
Total users checked: 5
Total access keys found: 6

Access keys within 365 days: 2
Access keys older than 365 days: 4
Users with old access keys: 2

WARNING: Found 4 access key(s) older than 365 days
These keys should be rotated as part of security best practices

Detailed report saved to: old_access_keys_report.txt
CSV export saved to: old_access_keys.csv

Recommendation: Rotate access keys at least every 90 days
To rotate: Create new key, update applications, then delete old key
```

---

# MFA Enabled Audit

## Overview

These scripts identify IAM users who do not have Multi-Factor Authentication (MFA) enabled. MFA is a critical security best practice that adds an extra layer of protection beyond just passwords.

**Key Features:**
- Identifies users without any MFA devices configured
- Shows count of MFA devices for users who have them
- Lists specific MFA device ARNs in detailed report
- Provides both detailed report and CSV export
- Color-coded console output for quick review

---

## Bash Script (Linux/macOS)

### File: `audit-mfa-enabled.sh`

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```bash
chmod +x audit-mfa-enabled.sh
./audit-mfa-enabled.sh
```

---

## PowerShell Script (Windows)

### File: `audit-mfa-enabled.ps1`

### Prerequisites

1. **PowerShell 5.0 or later**: Included with Windows 10/11 and Windows Server 2016+
2. **AWS CLI**: Must be installed and configured
3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```powershell
# Run the MFA audit
.\audit-mfa-enabled.ps1

# If you encounter execution policy errors:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Required AWS Permissions

Both scripts require the following IAM permissions:

- `iam:ListUsers`
- `iam:ListMFADevices`

---

## Output

Both scripts provide:

1. **Console output**: Color-coded results showing MFA status
   - ✓ (Green) - MFA enabled
   - ✗ (Red) - MFA not enabled

2. **Detailed report** (`users_without_mfa_report.txt`): Comprehensive audit showing:
   - Each user and their MFA status
   - Number of MFA devices (if any)
   - Specific device ARNs

3. **CSV export** (`users_without_mfa.csv`): Machine-readable format with columns:
   - UserName
   - MFA Enabled (Yes/No)
   - MFA Device Count
   - Device ARNs

## Example Output

```
==========================================
IAM MFA Audit
==========================================
Identifying users without MFA enabled

Fetching IAM users...
Found 6 IAM users

✓ admin-user - MFA enabled (1 device(s))
✗ service-account - MFA not enabled
✓ developer1 - MFA enabled (2 device(s))
✗ readonly-user - MFA not enabled
✓ developer2 - MFA enabled (1 device(s))
✗ temp-user - MFA not enabled

==========================================
Summary
==========================================
Total users checked: 6

Users with MFA enabled: 3
Users without MFA enabled: 3

WARNING: Found 3 user(s) without MFA enabled
These users should enable MFA to enhance account security

Users without MFA:
  ✗ service-account
  ✗ readonly-user
  ✗ temp-user

Detailed report saved to: users_without_mfa_report.txt
CSV export saved to: users_without_mfa.csv

Recommendation: Enable MFA for all users, especially those with console access
MFA adds an extra layer of security: Even if passwords are compromised, accounts remain protected
```

---

## Security Best Practices

### Password Change Policy

According to AWS best practices, IAM users should be able to change their own passwords. This allows for:

- **User autonomy**: Users can update expired or compromised passwords
- **Security compliance**: Meets common security framework requirements
- **Reduced admin overhead**: Users don't need to request password changes from administrators

### Access Key Rotation

AWS recommends rotating access keys regularly to reduce security risks:

- **Recommended rotation**: Every 90 days
- **Maximum age**: 365 days (for compliance purposes)
- **Risk mitigation**: Limits the window of exposure if keys are compromised
- **Compliance requirement**: Many security frameworks (CIS, PCI-DSS, SOC 2) mandate regular key rotation

### Multi-Factor Authentication (MFA)

MFA is one of the most effective security controls for protecting AWS accounts:

- **Critical protection**: Even if passwords are compromised, MFA prevents unauthorized access
- **Required for privileged users**: Essential for all users with administrative or sensitive permissions
- **Compliance mandate**: Required by most security frameworks (CIS AWS Foundations, PCI-DSS, SOC 2)
- **Types of MFA devices**:
  - Virtual MFA (Google Authenticator, Authy, Microsoft Authenticator)
  - Hardware MFA (YubiKey, Gemalto tokens)
  - SMS MFA (not recommended for root or privileged accounts)
- **Best practice**: Enable MFA for 100% of human users, especially those with console access

---

## Remediation

### Grant Password Change Permission

To grant users the ability to change their password, attach the AWS managed policy:

**Using AWS CLI (works in both Bash and PowerShell):**

```bash
# Attach to a specific user
aws iam attach-user-policy \
  --user-name USERNAME \
  --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword

# Attach to a group (recommended)
aws iam attach-group-policy \
  --group-name GROUPNAME \
  --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword
```

The `IAMUserChangePassword` policy allows users to change only their own password and manage their own MFA devices.

### Rotate Old Access Keys

To rotate access keys safely:

**Step 1: Create a new access key**
```bash
aws iam create-access-key --user-name USERNAME
```

**Step 2: Update all applications and services** to use the new access key

**Step 3: Test thoroughly** to ensure the new key works in all environments

**Step 4: Deactivate the old key** (allows for quick rollback if needed)
```bash
aws iam update-access-key --user-name USERNAME --access-key-id OLD_KEY_ID --status Inactive
```

**Step 5: Monitor for a few days**, then delete the old key
```bash
aws iam delete-access-key --user-name USERNAME --access-key-id OLD_KEY_ID
```

**Tip:** Never have more than one active access key per user during normal operations.

### Enable MFA for Users

There are two main ways to enable MFA: through the AWS Console (user self-service) or via AWS CLI (administrator).

#### Method 1: AWS Console (User Self-Service - Recommended)

Users can enable MFA for themselves through the AWS Console:

1. Sign in to the AWS Console
2. Click on your username in the top-right → Security credentials
3. In the "Multi-factor authentication (MFA)" section, click "Assign MFA device"
4. Choose MFA device type:
   - **Virtual MFA device** (Google Authenticator, Authy, etc.) - Most common
   - **Hardware TOTP token** (Physical device like YubiKey)
   - **FIDO security key** (USB security key)
5. Follow the on-screen instructions to complete setup

#### Method 2: AWS CLI (Virtual MFA - Administrator)

Administrators can enable virtual MFA for users via CLI:

**Step 1: Create a virtual MFA device**
```bash
aws iam create-virtual-mfa-device \
  --virtual-mfa-device-name USERNAME-mfa \
  --outfile /tmp/QRCode.png \
  --bootstrap-method QRCodePNG
```

**Step 2: User scans QR code** from `/tmp/QRCode.png` with their authenticator app

**Step 3: Enable the MFA device** (requires two consecutive authentication codes)
```bash
aws iam enable-mfa-device \
  --user-name USERNAME \
  --serial-number arn:aws:iam::ACCOUNT-ID:mfa/USERNAME-mfa \
  --authentication-code1 123456 \
  --authentication-code2 789012
```

**Note:** Replace `ACCOUNT-ID` with your AWS account ID, and use actual codes from the authenticator app.

#### Require MFA for Privileged Actions

Create a policy that requires MFA for sensitive operations:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyAllExceptListedIfNoMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

Apply this policy to groups or users to enforce MFA for all operations except MFA setup.

---

## Troubleshooting

### Common Issues (Both Scripts)

**Error: AWS CLI is not installed**
- Install AWS CLI following the [official documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

**Error: AWS credentials not configured or invalid**
- Run `aws configure` to set up your credentials
- Ensure your IAM user/role has the required permissions listed above

**Script runs but shows no users**
- Verify your AWS credentials have the `iam:ListUsers` permission
- Check that you're querying the correct AWS account with `aws sts get-caller-identity`

### Bash-Specific Issues

**Error: jq command not found**
- Install jq using the instructions in the Prerequisites section

**Permission denied when running script**
- Make the script executable: `chmod +x audit-iam-password-policy.sh`

### PowerShell-Specific Issues

**Error: Cannot be loaded because running scripts is disabled**
- You need to allow script execution: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- For more information, see [About Execution Policies](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)

**ConvertFrom-Json errors**
- Ensure you're using PowerShell 5.0 or later: `$PSVersionTable.PSVersion`
- Some AWS CLI output may need to be properly formatted; the script handles this automatically

## License

This project is provided as-is for AWS security auditing purposes.
