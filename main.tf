terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "example" {
  ami                    = data.aws_ssm_parameter.webserver-ami.value
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance.id]
  key_name               = aws_key_pair.aws-key.key_name

  tags = {
    Name = "ansible_install_mariadb"
  }
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key   = file(var.ssh_key_private)
      host        = self.public_ip
   }

  # Copy the playbook from local machine to EC2
  provisioner "file" {
    source      = "${path.root}/install_mariadb.yaml"
    destination = "install_mariadb.yaml"
  }

  # Copy the webserver content from local machine to EC2
  provisioner "file" {
    source      = "${path.root}/quotes.sql"
    destination = "quotes.sql"
  }

  # Execute a script on a remote resource
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y && sudo amazon-linux-extras install ansible2 -y",
      "sleep 60s",
      "sudo amazon-linux-extras install epel -y",
      "sudo yum-config-manager --enable epel",
      "ansible-playbook install_mariadb.yaml"
    ]
 }

}

resource "aws_security_group" "instance" {

  name = "ansible-security-group"

  #SSH
  ingress {
    description = "Allow SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #HTTP
  ingress {
    description = "Allow SSH traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

#Create key-pair for logging into EC2 
#======================================
resource "aws_key_pair" "aws-key" {
  key_name   = "ansible-db"
  public_key = file(var.ssh_key_public)
}

data "aws_ssm_parameter" "webserver-ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}