# Terraform Learning Notes

Part of my DevOps learning repo. Practice folder: `vpc_creation/` (builds a VPC on AWS).

**Schedule slot:** Tuesday, Week 2, about 3 to 4 hours.
**Topics:** providers, resources, variables, outputs, state.
**Goal:** finish the VPC script (VPC, subnets, IGW, route tables), apply it, verify in the AWS console, then destroy it.

---

## 0. Prerequisites

| Item | How to check |
|---|---|
| AWS account + IAM user with least privilege (done Monday) | `aws sts get-caller-identity` |
| AWS CLI configured | `aws configure`, then `aws s3 ls` |
| Terraform installed | `terraform -version` (1.5 or newer) |
| VS Code + HashiCorp Terraform extension | Extensions panel, search "HashiCorp Terraform" |

**Install on Windows (PowerShell):**
```powershell
winget install Hashicorp.Terraform
# or: choco install terraform
terraform -version
```

**IAM permissions for this lab:** for practice, attach `AmazonVPCFullAccess` to your IAM user. Later we tighten this.

---

## 1. Big picture: what is Terraform?

Terraform is Infrastructure as Code (IaC). You describe the infrastructure you want in `.tf` files (declarative), and Terraform works out what to create, change or delete to match.

The core workflow is always:

```
write  ->  terraform init  ->  terraform plan  ->  terraform apply  ->  (later) terraform destroy
```

| Command | What it does |
|---|---|
| `terraform init` | Downloads providers, sets up the working folder. Run once per folder, or after adding a provider. |
| `terraform fmt` | Auto-formats code. |
| `terraform validate` | Checks syntax and internal consistency. |
| `terraform plan` | Dry run: shows what will be created/changed/destroyed. |
| `terraform apply` | Does it (asks for `yes`). |
| `terraform destroy` | Deletes everything in the state. |
| `terraform show` | Prints the current state in readable form. |
| `terraform state list` | Lists resources Terraform is tracking. |
| `terraform output` | Prints output values. |

Symbols in a plan: `+` create, `~` update in place, `-` destroy, `-/+` replace.

---

## 2. Concepts, one by one

### 2.1 Providers
A provider is a plugin that talks to an API (AWS, Azure, Kubernetes, and so on).

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"     # any 5.x, never 6.x
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
```
- `terraform init` downloads the provider into `.terraform/` and writes `.terraform.lock.hcl` (commit this file, not the folder).
- Never put access keys in code. The provider reads `~/.aws/credentials` from `aws configure`.

### 2.2 Resources
A resource is one piece of infrastructure.

```hcl
resource "aws_vpc" "main" {        # resource "<TYPE>" "<LOCAL_NAME>"
  cidr_block = "10.0.0.0/16"
}
```
- Reference another resource's attribute: `aws_vpc.main.id`. This also creates a dependency, so Terraform builds the VPC before the subnet.
- Look up arguments in the docs: registry.terraform.io, then providers, then aws, then resources, then `aws_vpc`.

### 2.3 Data sources
Read-only lookups of things that already exist.
```hcl
data "aws_availability_zones" "available" { state = "available" }
# use as: data.aws_availability_zones.available.names[0]
```

### 2.4 Variables (inputs)
```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```
Types: `string`, `number`, `bool`, `list(string)`, `map(string)`, `object({...})`.
Use them as `var.vpc_cidr`.

Ways to set values (highest priority wins):
1. `-var="vpc_cidr=10.1.0.0/16"` on the command line
2. `*.auto.tfvars` files
3. `terraform.tfvars`
4. Environment variable `TF_VAR_vpc_cidr`
5. The `default` in the variable block

### 2.5 Outputs
Values printed after apply, and usable by other modules or projects.
```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}
```
View later with `terraform output vpc_id`.

### 2.6 Meta-arguments and expressions you need today
- `count = 2` creates 2 copies; use `count.index`.
- Splat `aws_subnet.public[*].id` collects a list of IDs.
- String interpolation: `"${var.project_name}-vpc"`.
- `length(list)` returns the size of a list.
- `tags = { Name = "..." }` on nearly every AWS resource.

### 2.7 State (very important)
- Terraform records what it created in `terraform.tfstate`. This is how it knows what exists.
- It compares **your code** with **state** with **real AWS**, then plans the difference.
- **Never edit state by hand. Never commit it to Git** (it can contain secrets). It is in `.gitignore`.
- Useful commands: `terraform state list`, `terraform state show aws_vpc.main`.
- Later, we move state to a remote backend (S3 + DynamoDB locking) for teams and for CI.

---

## 3. Architecture we are building

```
                 Internet
                    |
             [Internet Gateway]
                    |
   VPC 10.0.0.0/16  |
   +----------------+---------------------------+
   |  Public RT (0.0.0.0/0 -> IGW)              |
   |   public-1 10.0.1.0/24  (AZ a)             |
   |   public-2 10.0.2.0/24  (AZ b)             |
   |                                            |
   |  Private RT (local only)                   |
   |   private-1 10.0.11.0/24 (AZ a)            |
   |   private-2 10.0.12.0/24 (AZ b)            |
   +--------------------------------------------+
```
A subnet is "public" only because its route table sends `0.0.0.0/0` to an Internet Gateway.
The Kubernetes nodes will later live in these subnets.

---

## 4. Files in `vpc_creation/`

| File | Purpose |
|---|---|
| `providers.tf` | Terraform version, AWS provider, region |
| `variables.tf` | Input variable declarations |
| `main.tf` | VPC, subnets, IGW, route tables, associations |
| `outputs.tf` | IDs printed after apply |
| `terraform.tfvars` | Your values for the variables |

Terraform reads all `.tf` files in the folder together; the file names are only for readability.

---

## 5. Step-by-step lab (about 3 to 4 hours)

### Step 1: Setup (15 min)
```powershell
cd C:\Users\ADMIN\Devops\TH_Practice\Terraform_Folders\vpc_creation
aws sts get-caller-identity
terraform -version
```

### Step 2: Provider only (20 min)
1. Keep only `providers.tf` and `variables.tf`.
2. Run `terraform init`. Look at the new `.terraform/` folder and `.terraform.lock.hcl`.
3. Run `terraform validate`.

### Step 3: The VPC alone (30 min)
1. Add the `aws_vpc` block from `main.tf`.
2. `terraform plan`, then read it line by line.
3. `terraform apply`, type `yes`.
4. Check the AWS console (VPC dashboard, region ap-south-1), and run `terraform state list` and `terraform show`.

### Step 4: Add subnets and IGW (45 min)
1. Add the data source, the IGW and the public/private subnets.
2. `terraform plan` shows `+ 5 to add` (1 IGW, 4 subnets). Notice the VPC is not touched.
3. `terraform apply`.

### Step 5: Route tables (45 min)
1. Add the route tables and associations.
2. Plan, apply.
3. In the console: Route tables, open the public RT, and check the `0.0.0.0/0 -> igw-...` route and the subnet associations.

### Step 6: Outputs (15 min)
1. Add `outputs.tf`, then run `terraform apply` (it only prints new outputs).
2. `terraform output`, and `terraform output vpc_id`.

### Step 7: Experiments to understand variables and state (45 min)
1. Change `project_name` in `terraform.tfvars`. Plan shows tag updates in place (`~`).
2. Change `vpc_cidr`. Plan shows `-/+` replace (CIDR is immutable), and dependent resources too. **Do not apply.** Revert it.
3. Run `terraform plan -var="project_name=test"` to see the override.
4. **Drift test:** manually add a tag to the VPC in the console, then run `terraform plan` and see it want to remove that tag.
5. Run `terraform state list`, then `terraform state show aws_subnet.public[0]`.

### Step 8: Destroy (10 min)
```powershell
terraform destroy
```
The VPC, subnets, IGW and route tables are free, but destroying keeps the account clean. Re-apply anytime in about 1 minute.

### Step 9: Push to GitHub (15 min)
```powershell
cd C:\Users\ADMIN\Devops
git add terraform
git commit -m "Terraform part 1: VPC with subnets, IGW, route tables"
git push origin main
```
Confirm `.terraform/` and `*.tfstate` do not appear on GitHub.

---

## 6. Common errors

| Error | Cause / fix |
|---|---|
| `No valid credential sources found` | Run `aws configure`, or check `aws sts get-caller-identity` |
| `UnauthorizedOperation` | IAM user lacks VPC permissions |
| `Error acquiring the state lock` | An earlier run crashed; wait, or `terraform force-unlock <ID>` |
| `Invalid CIDR` / `CIDR conflicts` | Overlapping or malformed subnet ranges |
| `Unsupported argument` | Typo or wrong attribute name; check the registry docs |
| `DependencyViolation` on destroy | Something outside Terraform (an EC2, ENI) is still in the VPC |
| `Provider produced inconsistent result` | Re-run `terraform plan`; usually transient |

---

## 7. Self-check questions

1. What does `terraform init` do, and when do you re-run it?
2. What is the difference between a resource and a data source?
3. What is the order of variable precedence?
4. Why is `terraform.tfstate` not committed to Git?
5. What makes a subnet "public"?
6. Why does Terraform build the VPC before the subnets, though you never said so?
7. What does `-/+` mean in a plan?
8. What is drift, and how does `plan` reveal it?

---

## 8. Cheat sheet

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
terraform state list
terraform destroy -auto-approve   # only in labs
```

---

## 9. Practice challenges (if time remains)

- Add a third AZ and a third public/private subnet by only editing the `.tfvars` file.
- Add a `variable "environment"` (dev/prod) and put it into every `Name` tag.
- Add `locals { common_tags = {...} }` and use `tags = local.common_tags`.
- Add a Security Group (allow 22 and 80) in the VPC.
- Read about `terraform import` (adopt an existing resource into state).

## 10. Next (Wednesday)

Terraform part 2: EC2, security groups, key pairs, user_data, and using this VPC's subnet IDs. The Kubernetes nodes will be built on top of this.

## References

- Terraform docs: https://developer.hashicorp.com/terraform/docs
- AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS VPC basics: https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html
