#!/bin/bash
# User data script to install Java on Amazon Linux 2023

# Update system
yum update -y

# Install Java 17
yum install java-17-amazon-corretto-devel -y

# Install monitoring tools
yum install htop -y

# Create directory for application
mkdir -p /home/ec2-user/uploads/images
chown -R ec2-user:ec2-user /home/ec2-user/uploads

echo "Java installation complete"
java -version
