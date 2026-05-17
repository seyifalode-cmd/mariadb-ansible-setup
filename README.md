# **MariaDB Ansible Setup**

Self-contained Terraform and Ansible project that provisions an AWS EC2 instance, installs Ansible, and runs a playbook to deploy a fully configured MariaDB database — including database creation, user provisioning, and seed data import — all in a single `terraform apply`.

---

## Project at a Glance

| | |
|---|---|
| **Tools Used** | Terraform, Ansible, MariaDB, AWS EC2, AWS SSM Parameter Store |
| **Platform** | Amazon Web Services (us-east-1) |
| **Languages** | HCL (Terraform), YAML (Ansible), SQL |
| **What It Does** | Provisions an EC2 instance, installs Ansible and MariaDB, creates a database and user, and imports seed data — fully automated end to end |

---

## The Problem This Project Solves

Setting up a database server in a cloud environment typically involves multiple manual steps that are easy to get wrong: launching the instance, installing the database engine, enabling the service, installing the correct Python library so that configuration management tools can interact with MySQL, creating the database schema, provisioning users with the right privileges, and loading initial data. Each of these steps represents a potential failure point, and any error that happens in the middle of the sequence leaves the server in a partially configured state.

This project collapses all of that into a single declarative workflow. Terraform provisions the EC2 instance, copies both the Ansible playbook and the SQL seed file onto the machine, and then runs a `remote-exec` provisioner that installs Ansible and immediately executes the playbook against `localhost`. The playbook handles every layer of database configuration: installing `mariadb-server` via `yum`, starting and enabling the service through `systemd`, installing `python2-PyMySQL` so that Ansible's `mysql_db` and `mysql_user` modules work, creating the `bobdata` database, creating the `Bob` user, and finally running the SQL import.

The end result is a fully functional MariaDB server that can be validated the moment `terraform apply` completes. This pattern is directly applicable in environments where a database tier needs to be stood up quickly and repeatably — for example, in a CI pipeline, a development environment, or a training lab.

---

## Architecture

```
Local Machine
     |
     | terraform apply
     v
+----------------------------------+
|   Terraform (HCL)                |
|   - aws_ssm_parameter (AMI)      |
|   - aws_key_pair                 |
|   - aws_security_group           |
|   - aws_instance                 |
|     - provisioner "file"         |
|       install_mariadb.yaml -->   |
|       quotes.sql -->             |
|     - provisioner "remote-exec"  |
+----------------------------------+
     |
     | SSH (provisioners)
     v
+----------------------------------------------+
|  EC2 Instance: "ansible_install_mariadb"     |
|  AMI: Amazon Linux 2 (latest, via SSM)       |
|  Instance Type: t3.micro | Region: us-east-1 |
|  Security Group: SSH(22), HTTP(80)           |
|                                              |
|  remote-exec steps:                          |
|    1. yum update                             |
|    2. amazon-linux-extras install ansible2   |
|    3. sleep 60s (package settling)           |
|    4. install epel                           |
|    5. yum-config-manager --enable epel       |
|    6. ansible-playbook install_mariadb.yaml  |
|                                              |
|  Ansible playbook (localhost):               |
|    - yum: mariadb-server                     |
|    - systemd: mariadb (started + enabled)    |
|    - yum: python2-PyMySQL                    |
|    - mysql_db: bobdata                       |
|    - mysql_user: Bob / pa55word              |
|    - shell: mysql -u root bobdata < quotes.sql
+----------------------------------------------+
     |
     | Terraform output
     v
  Ansible-Install_dbserver-PublicIP
```

---

## Repository Structure

```
mariadb-ansible-setup/
├── main.tf                 # EC2, security group, key pair, file + remote-exec provisioners
├── variables.tf            # SSH key path variables
├── outputs.tf              # Exports the EC2 public IP
├── install_mariadb.yaml    # Ansible playbook: full MariaDB installation and configuration
├── quotes.sql              # Seed data: SteveJobsQuotes table (20 rows)
└── .gitignore
```

---

## How It Works

**Step 1 — Terraform resolves the AMI.**
The `aws_ssm_parameter` data source fetches the current Amazon Linux 2 HVM AMI ID from SSM at plan time — no hardcoded AMI required.

**Step 2 — EC2 instance is launched.**
The instance is tagged `ansible_install_mariadb` and associated with a security group allowing inbound SSH (22) and HTTP (80). The SSH key pair is registered from the local public key file.

**Step 3 — Files are transferred.**
Two `file` provisioners copy the Ansible playbook (`install_mariadb.yaml`) and the SQL seed file (`quotes.sql`) from the local machine to the home directory of `ec2-user` on the new instance.

**Step 4 — Ansible is installed and the playbook is executed.**
A `remote-exec` provisioner runs an inline script: updates the OS, installs Ansible 2 via `amazon-linux-extras`, waits 60 seconds for packages to settle, enables EPEL, and then runs `ansible-playbook install_mariadb.yaml`.

**Step 5 — The Ansible playbook configures MariaDB end to end.**
The playbook runs against `localhost` as root (`become: true`). It installs and starts MariaDB, installs the Python MySQL client library, creates the `bobdata` database and the `Bob` user, and finally imports `quotes.sql` to create the `SteveJobsQuotes` table and populate it with 20 rows of seed data.

---

## Walkthrough

```bash
# 1. Initialize Terraform
terraform init

# 2. Preview what will be created
terraform plan

# 3. Apply — this provisions EC2, installs Ansible, and runs the full playbook
terraform apply \
  -var="ssh_key_private=~/.ssh/id_ed25519" \
  -var="ssh_key_public=~/.ssh/id_ed25519.pub" \
  -auto-approve

# The apply will take 3-5 minutes as it:
# - Launches EC2
# - Waits for SSH to become available
# - Runs the remote-exec provisioner (yum + ansible-playbook)

# 4. Get the server's public IP
terraform output Ansible-Install_dbserver-PublicIP

# 5. SSH in and validate the database
ssh -i ~/.ssh/id_ed25519 ec2-user@<public-ip>

# On the remote server:
mysql -u Bob -ppa55word bobdata -e "SHOW TABLES;"
mysql -u Bob -ppa55word bobdata -e "SELECT COUNT(*) FROM SteveJobsQuotes;"
mysql -u Bob -ppa55word bobdata -e "SELECT * FROM SteveJobsQuotes LIMIT 3;"

# 6. Tear down
terraform destroy -auto-approve
```

---

## How to Reproduce

**Prerequisites**

- Terraform >= 1.0.0
- AWS account with credentials configured
- SSH key pair on your local machine

```bash
# Clone the repository
git clone https://github.com/seyifalode-cmd/mariadb-ansible-setup.git
cd mariadb-ansible-setup

# Initialize Terraform
terraform init

# Apply — replace key paths if yours differ from the defaults
terraform apply \
  -var="ssh_key_private=${HOME}/.ssh/id_ed25519" \
  -var="ssh_key_public=${HOME}/.ssh/id_ed25519.pub" \
  -auto-approve

# Validate
ssh -i ~/.ssh/id_ed25519 ec2-user@$(terraform output -raw Ansible-Install_dbserver-PublicIP) \
  "mysql -u Bob -ppa55word bobdata -e 'SELECT COUNT(*) FROM SteveJobsQuotes;'"

# Clean up
terraform destroy -auto-approve
```

---

## Seed Data

The `quotes.sql` file creates the `SteveJobsQuotes` table with an `id` (INT PRIMARY KEY) and `quote` (VARCHAR 255) column, then inserts 20 rows. It is used to confirm that the database, the user permissions, and the SQL import chain all worked correctly in a single verifiable query.

---

## Comparison with `ansible-control-node-setup`

The `ansible-control-node-setup` project contains a similar MariaDB playbook (`install_mariadb.yaml`), but that playbook is designed to run from a separate control node against a remote `[databases]` inventory group. This project (`mariadb-ansible-setup`) is self-contained: both Ansible and MariaDB run on the same EC2 instance, with the playbook targeting `localhost`. This makes it ideal for isolated testing, quick demos, or environments where a separate control node is not needed.

---

## Related Projects

- `ansible-sandbox-ec2` — Minimal single-node Ansible sandbox
- `ansible-control-node-provisioner` — Control node provisioner with SSH key generation
- `ansible-managed-nodes-provisioner` — Multi-node fleet provisioner
- `ansible-control-node-setup` — Remote playbooks for web and database roles
- `mariadb-ansible-setup` — **This project** — Self-contained MariaDB provisioning

---

*Oluwaseyi Michael Falode · Cybersecurity & Cloud Security Engineer · Toronto, ON*
