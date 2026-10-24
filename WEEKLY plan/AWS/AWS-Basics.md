# Day: AWS Core – IAM, EC2, S3, CLI

**Goal:** IAM user with least privilege, `aws configure` working, upload a file to S3.
**Practice setup:** AWS account (free tier) + Windows laptop (PowerShell / VS Code) + the EC2 instance you already use.

> Commands marked **[Laptop]** run in PowerShell on your Windows laptop.
> Commands marked **[EC2]** run on your Amazon Linux instance.
> Always work in one region (example: `ap-south-1`, Mumbai). Pick one and stay with it.

---

## 0. Safety first (do this before anything else)

1. Enable **MFA** on the root account (Console → top-right menu → Security credentials).
2. Never create access keys for the root account. Never use root for daily work.
3. Set a budget alert: Console → Billing → Budgets → *Zero spend budget* (or $5).
4. Never commit keys to GitHub. Add this to your `.gitignore` now:
   ```
   .aws/
   *.pem
   *.tfstate
   *.tfvars
   credentials
   ```

---

## 1. Concepts: AWS basics

| Term | Meaning |
|---|---|
| Region | A geographic area (Mumbai = `ap-south-1`). Most resources live in one region. |
| Availability Zone (AZ) | One or more data centers in a region (`ap-south-1a`, `1b`). |
| Account | Your billing and security boundary. |
| ARN | Unique resource ID, e.g. `arn:aws:s3:::my-bucket`. |
| Shared responsibility | AWS secures the cloud; you secure what you put in it (IAM, security groups, data). |

---

## 2. IAM (Identity and Access Management)

### 2.1 Concepts

- **User**: a person or app with long-term credentials (password and/or access keys).
- **Group**: collection of users; attach policies to the group.
- **Role**: an identity with *temporary* credentials, assumed by a user, service (EC2), or another account. No password or keys.
- **Policy**: JSON document that allows or denies actions on resources.
- **Least privilege**: grant only the permissions needed, nothing more.

Policy anatomy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::YOUR-BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::YOUR-BUCKET/*"
    }
  ]
}
```

Evaluation rules: everything is denied by default; an explicit **Deny** always wins over Allow.

Policy types to know: AWS managed, customer managed, inline, resource-based (e.g. bucket policy), permission boundary, SCP (Organizations).

### 2.2 Lab 1: Create an admin user and a least-privilege user (Console)

1. Console → IAM → **Users → Create user** → name `tharun-admin` → give console access → attach `AdministratorAccess` (directly or via a group named `admins`). Use this for daily work instead of root.
2. Create a second user `s3-practice-user`:
   - No console access needed.
   - Do not attach any policy yet.
3. Create a **customer managed policy** `S3PracticeBucketAccess` using the JSON above (replace `YOUR-BUCKET` with your unique bucket name, for example `tharun-practice-2026-123`).
4. Attach that policy to `s3-practice-user`.
5. For `s3-practice-user` → Security credentials → **Create access key** → use case *CLI* → download the CSV. This is the only time you see the secret.

### 2.3 Lab 2: Use the IAM Policy Simulator

Console → IAM → Policy simulator (or search "IAM Policy Simulator"). Select `s3-practice-user`, test `s3:PutObject` on your bucket (should be allowed) and `ec2:DescribeInstances` (should be denied). This shows how least privilege works without touching real resources.

### 2.4 Lab 3: Roles (needed for EC2 later)

1. IAM → Roles → Create role → Trusted entity: **AWS service → EC2**.
2. Attach `AmazonS3ReadOnlyAccess`.
3. Name it `ec2-s3-readonly-role`. You will attach this to your EC2 instance in section 4.

### 2.5 Advanced IAM topics (read and try after the basics)

- Permission boundaries and how they cap what a user can grant.
- `sts assume-role` from the CLI (temporary credentials).
- Conditions in policies (`aws:SourceIp`, `aws:MultiFactorAuthPresent`, `aws:RequestedRegion`).
- Access Analyzer and the *Last accessed* tab to trim unused permissions.
- IAM Identity Center (SSO) as the modern alternative to long-lived keys.
- Rotating access keys and deleting unused ones.

---

## 3. AWS CLI

### 3.1 Install and verify [Laptop]

Install the AWS CLI v2 MSI from the official AWS docs, then open a **new** PowerShell window:

```powershell
aws --version
```

### 3.2 Configure with a named profile [Laptop]

```powershell
aws configure --profile s3practice
# AWS Access Key ID:     <from the CSV>
# AWS Secret Access Key: <from the CSV>
# Default region name:   ap-south-1
# Default output format: json
```

Where it is stored (do not share or commit these):

```
C:\Users\ADMIN\.aws\credentials
C:\Users\ADMIN\.aws\config
```

Use the profile:

```powershell
$env:AWS_PROFILE = "s3practice"      # for this PowerShell session
aws sts get-caller-identity           # shows which IAM identity you are
```

You should see the ARN of `s3-practice-user`. This is your first check that the setup works.

### 3.3 Handy CLI features

```powershell
aws configure list
aws configure list-profiles
aws iam list-users --profile tharun-admin          # needs admin permissions
aws s3 ls help                                     # built-in help for any command
aws ec2 describe-regions --output table
aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,State.Name]" --output table
```

Output formats: `json`, `table`, `text`, `yaml`. Filter with `--query` (JMESPath).

### 3.4 Prove least privilege works [Laptop]

```powershell
aws ec2 describe-instances --profile s3practice
```

Expected: **AccessDenied**. That is correct. This user can only touch the S3 bucket.

---

## 4. EC2

### 4.1 Concepts

- **Instance**: a virtual server. **AMI**: the image it boots from. **Instance type**: CPU/RAM size (`t2.micro` / `t3.micro` is free-tier eligible).
- **Key pair**: SSH login key (`.pem`).
- **Security group**: stateful firewall at the instance level (inbound rules; outbound is open by default).
- **EBS**: the disk. **Elastic IP**: a fixed public IP. **User data**: script that runs on first boot.
- **Instance profile**: how an IAM role is attached to an EC2 instance.
- Lifecycle: pending → running → stopping → stopped → terminated. A stopped instance does not bill for compute but its EBS volume still bills.

### 4.2 Lab 4: Launch an instance (Console)

1. EC2 → **Launch instance** → name `aws-practice`.
2. AMI: Amazon Linux 2023. Type: `t2.micro` or `t3.micro`.
3. Key pair: create `aws-practice-key` (.pem) and save it safely.
4. Network: security group allowing **SSH (22) from My IP only** (not 0.0.0.0/0).
5. Launch.

### 4.3 Lab 5: Connect from your laptop [Laptop]

```powershell
ssh -i C:\Users\ADMIN\.ssh\aws-practice-key.pem ec2-user@<PUBLIC_IP>
```

If Windows complains about permissions on the key file:

```powershell
icacls C:\Users\ADMIN\.ssh\aws-practice-key.pem /inheritance:r
icacls C:\Users\ADMIN\.ssh\aws-practice-key.pem /grant:r "$($env:USERNAME):(R)"
```

### 4.4 Lab 6: Attach the IAM role to the instance

Console → EC2 → select instance → **Actions → Security → Modify IAM role** → choose `ec2-s3-readonly-role`.

Then on the instance [EC2]:

```bash
aws --version                      # preinstalled on Amazon Linux
aws sts get-caller-identity        # shows the ROLE, no keys configured!
aws s3 ls                          # works because of the role (read-only)
```

This is the key idea: **on EC2, use roles, never put access keys on the server.**

### 4.5 Lab 7: Create and manage EC2 from the CLI [Laptop]

Use your admin profile for this one:

```powershell
$env:AWS_PROFILE = "tharun-admin"
aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PublicIpAddress]" --output table
aws ec2 stop-instances  --instance-ids i-xxxxxxxxxxxxxxxxx
aws ec2 start-instances --instance-ids i-xxxxxxxxxxxxxxxxx
```

### 4.6 Advanced EC2 topics

- Security group rules vs network ACLs.
- Elastic IP vs auto-assigned public IP (changes on stop/start).
- EBS snapshots, resizing a volume, creating an AMI from an instance.
- Instance metadata service (IMDSv2): `curl` from inside the instance returns the role's temporary credentials.
- Pricing models: On-Demand, Reserved, Savings Plans, Spot.
- Systems Manager Session Manager as a keyless alternative to SSH.

---

## 5. S3

### 5.1 Concepts

- **Bucket**: container with a **globally unique** name. **Object**: file + metadata, identified by a **key** (path-like name).
- S3 is flat; "folders" are just key prefixes.
- Block Public Access is **on by default**. Keep it on.
- Storage classes: Standard, Intelligent-Tiering, Standard-IA, Glacier tiers (cheaper, slower).
- Versioning, lifecycle rules, encryption at rest (SSE-S3 default), bucket policies, pre-signed URLs.

### 5.2 Lab 8: Create a bucket and upload [Laptop]

Use the admin profile to create the bucket (the least-privilege user cannot create buckets, by design):

```powershell
$env:AWS_PROFILE = "tharun-admin"
aws s3 mb s3://tharun-practice-2026-123 --region ap-south-1
```

Switch to the least-privilege user and upload:

```powershell
$env:AWS_PROFILE = "s3practice"
"hello from my laptop" | Out-File hello.txt -Encoding utf8
aws s3 cp hello.txt s3://tharun-practice-2026-123/hello.txt
aws s3 ls s3://tharun-practice-2026-123/
aws s3 cp s3://tharun-practice-2026-123/hello.txt downloaded.txt
```

Success here completes the day's goal: **IAM user with least privilege + `aws configure` + upload to S3.**

### 5.3 Lab 9: Sync a folder

```powershell
mkdir site-test
"<h1>Hello S3</h1>" | Out-File site-test\index.html -Encoding utf8
aws s3 sync .\site-test s3://tharun-practice-2026-123/site-test/
aws s3 sync s3://tharun-practice-2026-123/site-test/ .\restore-test\
aws s3 rm s3://tharun-practice-2026-123/site-test/ --recursive
```

Use `--dryrun` first on `sync` and `rm` when you are unsure.

### 5.4 Lab 10: Download on EC2 using the role [EC2]

```bash
aws s3 ls s3://tharun-practice-2026-123/
aws s3 cp s3://tharun-practice-2026-123/hello.txt .
cat hello.txt
aws s3 cp hello.txt s3://tharun-practice-2026-123/from-ec2.txt   # should FAIL (role is read-only)
```

The failed upload proves the role is least-privilege.

### 5.5 Lab 11: Versioning and pre-signed URL [Laptop]

```powershell
$env:AWS_PROFILE = "tharun-admin"
aws s3api put-bucket-versioning --bucket tharun-practice-2026-123 --versioning-configuration Status=Enabled
aws s3 cp hello.txt s3://tharun-practice-2026-123/hello.txt        # upload again after editing it
aws s3api list-object-versions --bucket tharun-practice-2026-123 --prefix hello.txt

aws s3 presign s3://tharun-practice-2026-123/hello.txt --expires-in 300
```

Open the presigned URL in a browser: it works for 5 minutes without any credentials.

### 5.6 Advanced S3 topics

- Bucket policies vs IAM policies (when each is evaluated).
- Lifecycle rules (move to Glacier after N days, expire old versions).
- Server-side encryption with KMS keys.
- Static website hosting and CloudFront.
- Multipart upload, `aws s3api` low-level commands.
- Event notifications to Lambda/SQS.

---

## 6. Cleanup (avoid surprise bills)

```powershell
# Laptop (admin profile)
aws s3 rm s3://tharun-practice-2026-123 --recursive
aws s3api delete-bucket --bucket tharun-practice-2026-123
# If versioning was enabled, delete all versions in the Console (S3 → bucket → Empty), then delete the bucket.
```

- EC2: **Terminate** the instance (stop alone is not enough if you are done). Release any Elastic IP.
- IAM: deactivate and delete the practice access key when finished.
- Console → Billing → Cost Explorer next day to confirm no charges.

---

## 7. Checklist

- [ ] Root MFA on, budget alert set
- [ ] Admin IAM user created, used for daily work
- [ ] `s3-practice-user` created with custom least-privilege policy
- [ ] `aws configure --profile s3practice` works, `sts get-caller-identity` shows the right user
- [ ] `ec2 describe-instances` is denied for the practice user (proves least privilege)
- [ ] EC2 instance launched and reachable over SSH
- [ ] IAM role attached to EC2, `aws s3 ls` works without keys
- [ ] File uploaded to S3 from laptop; downloaded on EC2
- [ ] Versioning and pre-signed URL tested
- [ ] Everything cleaned up
- [ ] README committed and pushed to GitHub (no keys inside!)

---

## 8. Interview questions to practice

1. Difference between an IAM user, group, and role?
2. How does AWS evaluate a request when there is both an Allow and a Deny?
3. Why should EC2 use a role instead of access keys?
4. What is a security group, and is it stateful?
5. Does stopping an EC2 instance stop all charges?
6. How do you make an S3 object accessible for a limited time without making it public?
7. What does `aws sts get-caller-identity` tell you?

---

## 9. Push to GitHub

```powershell
cd C:\Users\ADMIN\Devops
git add .
git commit -m "Add AWS core learning README"
git push
```
