# POC — PCI DSS on AWS

## Overview

![PCI DSS Architecture](poc-pci-dss.drawio.png)

---

## Endpoints

| Path             | URL                                        |
|------------------|--------------------------------------------|
| App              | <https://pci-dss-dev.pomeshk.in>           |
| ALB health check | <https://pci-dss-dev.pomeshk.in/alb-check> |

---

## Pre-requirements

| Requirement            | Details                                                                                                                                                                        |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| HTTP support           | Application uses HTTP and can leverage ALB.                                                                                                                                    |
| Git-based execution    | `terragrunt` runs from a git repo — [`get_repo_root()`](https://terragrunt.gruntwork.io/docs/reference/built-in-functions/#get_repo_root) will fail otherwise.                 |
| Route 53 NS delegation | After `basement` is applied, a Route 53 public zone is created. **Before** applying subsequent layers, create NS records in the parent zone pointing to the newly created zone. |

---

## Terragrunt Structure

- The `env` folder contains the IaC structure: `<ENV>/<AWS_REGION>/<INFRA_LAYER/STACK>`.
- The `modules` folder contains Terraform code structured as modules for each `<INFRA_LAYER>`. Module names match their corresponding layer names.

---

## Terragrunt Hierarchy

1. `basement` — CloudTrail, IAM roles, KMS keys, public Route 53 zone, S3 buckets
2. `network` — VPC components, ACLs and security groups, ALB, ACM, private Route 53 zone
3. `compute` — EC2 with MySQL, ASG with app

---

## Codebase References

- ACL config: [terragrunt/modules/network/net-vpc.tf](terragrunt/modules/network/net-vpc.tf#L4)
- Security Group config: [terragrunt/modules/network/net-sg.tf](terragrunt/modules/network/net-sg.tf#L3)
- ALB with external IP and SSL certificate attached: [terragrunt/modules/network/net-elb.tf](terragrunt/modules/network/net-elb.tf#L50)
- Inbound traffic limited to a list of IP addresses #1: [terragrunt/root.hcl](terragrunt/root.hcl#L25)
- Inbound traffic limited to a list of IP addresses #2: [terragrunt/modules/network/net-sg.tf](terragrunt/modules/network/net-sg.tf#L15)
- Allowed domains: [terragrunt/modules/network/net-route53.tf](terragrunt/modules/network/net-route53.tf#L15)
- CloudTrail: [terragrunt/modules/basement/base-cloudtrail.tf](terragrunt/modules/basement/base-cloudtrail.tf#L6)

---

## Traffic Restriction Details

- **AWS Network ACLs** are stateless. Connection state is not tracked, so accept rules must be defined explicitly for each packet going to, from, or through an attached subnet. For example, to allow outbound TCP/443, return traffic on ephemeral ports 1024–65535 must also be explicitly allowed.
- **AWS Security Groups** are stateful. Connection state is tracked, so only the initial connection needs to be allowed — no ephemeral port rules are required.

---

## How to Run

```bash
# Ensure AWS profile is set up
cd terragrunt
tg hcl fmt && tf fmt -recursive
cd env/dev
tg run --all init --backend-bootstrap  # Run once to create the S3 bucket for Terraform state
tg run --all apply
```

---

## PCI DSS Requirements (POC Scope)

- 🔒 **No unencrypted traffic** — even inside the VPC (ALB → EC2-app and EC2-app → MySQL use TLS v1.3)
- 🏗️ **Subnet segmentation** — subnets are separated by type (public for ALB and NAT GW, private for app, database for EC2 MySQL)
- 🚦 **Least-privilege** — traffic is allowed by the principle of least privilege
- 💾 **Encryption at rest** — S3, EBS, logs, and all other data stores are encrypted
- 🔍 **Route 53 Resolver Firewall**
- 🔥 **AWS Network Firewall** enabled *(skipped — cost)*
- 🛡️ **WAF** attached to ALB *(skipped)*
- 📋 **Logging** enabled for all operations

---

## How to Allow Access Only to Accepted Domains

The best AWS option to restrict traffic to allowed domains is to use a combination of Route 53 Resolver DNS Firewall and Network Firewall. Network Firewall costs approximately $0.40/hour per endpoint, so for this POC only Route 53 Resolver DNS Firewall is used.

---

## Allowlisted Domains

- `example.com.`
- `secureweb.com.`
- `*.${AWS_REGION}.amazonaws.com.` (for VPC endpoints)

---

## Documentation

- [AWS Network Firewall — Central Inspection VPC](https://catalog.workshops.aws/networkfirewall/en-US/setup/centralmodel/inspectionvpc)
- [Secure VPC DNS Resolution with Route 53 Resolver DNS Firewall](https://aws.amazon.com/blogs/networking-and-content-delivery/secure-your-amazon-vpc-dns-resolution-with-amazon-route-53-resolver-dns-firewall/)
- [Stateful Rule Groups — Domain Names](https://docs.aws.amazon.com/network-firewall/latest/developerguide/stateful-rule-groups-domain-names.html)

---

## TODO

- [ ] Fix ALB logging (S3 bucket policy / ACL)
