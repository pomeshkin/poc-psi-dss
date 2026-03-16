# Task 1. Generate packer HCL configuration
- Use AWS Systems Manager (SSM) for connection
- Use t3.small
- Create AMI with name "pci-dss-nginx-mysql-YYYY-MM-DD-hh-mm"
- Use AWS profile pci-dss-dev
- Use latest "Amazon Linux 2023 AMI 2023.10.2026*"
- Find IAM instance profile by name "dev-ec2-default-use2"
- Find VPC by tag Name=dev
- Find subnet by tag Name=dev-public-us-east-2a
- Find security group by tag Name=dev-packer
- Add user data to install and start AWS SSM agent before packer script execution
- Create self-signed TLSv1.3 certificate for Nginx
- Install Nginx with dummy start page and HTTPs listener with a created certificate. Disable Nginx service
- Install MySQL 9.6 with TLSv1.3 enabled. Disable MySQL service

# Task 2. Create README.md in the "<REPO_ROOT>/packer" directory
- Add command how to start Nginx service via user data
- Add command how to start MySQL service via user data
- Add MySQL database creation and password reset example (will be exeecuted in user data)
- Add MySQL connection test example
