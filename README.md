# AWS IAM Security Audit Scripts

This repository contains security audit scripts for AWS IAM to help identify potential security issues and maintain compliance with AWS best practices.

## Available Scripts

### IAM Password Policy Audit
Identifies IAM users who do not have the "IAMUserChangePassword" policy attached.
- `audit-iam-password-policy.sh` - Bash script for Linux/macOS
- `audit-iam-password-policy.ps1` - PowerShell script for Windows

### Old Access Keys Audit
Identifies IAM users with access keys older than 365 days.
- `audit-old-access-keys.sh` - Bash script for Linux/macOS
- `audit-old-access-keys.ps1` - PowerShell script for Windows

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
