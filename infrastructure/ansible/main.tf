terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  # secret_key = ""
  # access_key = ""
}

locals {
  user = "mecit"
}

resource "aws_instance" "nodes" {
  ami = element(var.myami, count.index)
  instance_type = var.instancetype
  count = var.num
  key_name = var.mykey
  vpc_security_group_ids = [aws_security_group.tf-sec-gr.id]
  tags = {
    Name = "${element(var.tags, count.index)}-${local.user}"
  }
}


resource "aws_instance" "backend" {
  ami                    = var.myami[3] 
  instance_type          = "t3a.medium" 
  count                  = 1
  key_name               = var.mykey
  vpc_security_group_ids = [aws_security_group.tf-sec-gr.id]
  tags = {
    Name = "${var.tags[3]}-${local.user}"
  }

  root_block_device {
    volume_size = 15 
  }
}



data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "tf-sec-gr" {
  name = "ai-aplication-ansible-sec-gr-${local.user}"
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = "ai-aplication-ansible-sec-gr-${local.user}"
  }

  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = -1
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "null_resource" "config" {
  depends_on = [aws_instance.nodes[0]]
  connection {
    host = aws_instance.nodes[0].public_ip
    type = "ssh"
    user = "ec2-user"
    private_key = file("~/.ssh/${var.mykey}.pem")
    # Do not forget to define your key file path correctly!
  }

  provisioner "file" {
    source = "./.ansible.cfg"
    destination = "/home/ec2-user/.ansible.cfg"
  }

  provisioner "local-exec" {
    command = "tar -czf ansible.tar.gz -C ./ansible ."
}

  provisioner "file" {
    source      = "ansible.tar.gz"
    destination = "/home/ec2-user/ansible.tar.gz"
}



  provisioner "file" {
    # Do not forget to define your key file path correctly!
    source = "~/.ssh/${var.mykey}.pem"
    destination = "/home/ec2-user/${var.mykey}.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname Control-Node",
      "sudo dnf update -y",
      "sudo dnf install ansible -y",
      "echo [webservers] >> inventory.txt",
      "echo frontend ansible_host=${aws_instance.nodes[1].private_ip} ansible_ssh_private_key_file=~/${var.mykey}.pem ansible_user=ec2-user >> inventory.txt",
      "echo backend ansible_host=${aws_instance.backend[0].private_ip} ansible_ssh_private_key_file=~/${var.mykey}.pem ansible_user=ec2-user >> inventory.txt",
      "echo [Mysqlservers] >> inventory.txt",
      "echo mysql ansible_host=${aws_instance.nodes[2].private_ip} ansible_ssh_private_key_file=~/${var.mykey}.pem ansible_user=ec2-user >> inventory.txt",
      "chmod 400 ${var.mykey}.pem",
      "echo frontend private ip=${aws_instance.nodes[1].private_ip} >> ip.txt",
      "echo mysql private ip=${aws_instance.nodes[2].private_ip} >> ip.txt",
      "echo mysql public ip=${aws_instance.nodes[2].public_ip} >> ip.txt",
      "echo backend public ip=${aws_instance.backend[0].public_ip} >> ip.txt",
      "echo backend private ip=${aws_instance.backend[0].private_ip} >> ip.txt",
    ]
  }
}

output "controlnodeip" {
  value = aws_instance.nodes[0].public_ip
}