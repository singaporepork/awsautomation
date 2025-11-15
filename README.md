# AWS IAM Password Policy Audit

This repository contains scripts to identify IAM users who do not have the "IAMUserChangePassword" policy attached, either directly or through group membership.

**Available Scripts:**
- `audit-iam-password-policy.sh` - Bash script for Linux/macOS
- `audit-iam-password-policy.ps1` - PowerShell script for Windows

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

## Security Best Practices

According to AWS best practices, IAM users should be able to change their own passwords. This allows for:

- **User autonomy**: Users can update expired or compromised passwords
- **Security compliance**: Meets common security framework requirements
- **Reduced admin overhead**: Users don't need to request password changes from administrators

---

## Remediation

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
