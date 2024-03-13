terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
locals {
  env = "test"
}
module "vpc" {
  source                     = "../Terraform_modules/terraform-aws-vpc"
  azs                        = ["ap-south-1a", "ap-south-1b"]
  env                        = local.env
  vpc_cidr_block             = "20.93.0.0/16"
  private_subnet_cidr_blocks = []
  public_subnet_cidr_blocks  = ["20.93.0.64/26", "20.93.0.128/26"]
}
module "lb" {
  source             = "../Terraform_modules/terraform-aws-lb"
  env                = local.env
  lb_security_groups = [module.instance.public_sg_id]
  subnet_ids         = module.vpc.public_subnet_ids
  vpc_id             = module.vpc.vpc_id
  target_type        = "ip"
}

module "instance" {
  source = "../Terraform_modules/terraform-aws-instance"
  env    = local.env
  ami_id = "ami-03bb6d83c60fc5f7c"
  public_sg_egress_with_cidr_blocks = [{
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }]
  public_sg_ingress_with_cidr_blocks = [{
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }]
  private_subnet_ids = []
  public_subnet_ids  = []
  vpc_id             = module.vpc.vpc_id
  private_key        = file("./mykeypair.pem")
  user_data          = ""


}

module "asg" {
  source              = "../Terraform_modules/terraform-aws-asg"
  env                 = local.env
  ami_id              = "ami-03bb6d83c60fc5f7c"
  alb_arn             = module.lb.target_group_arn
  azs                 = ["ap-south-1a", "ap-south-1b"]
  lb_security_groups  = [module.instance.public_sg_id]
  desired_size        = 1
  instance_type       = "t2.micro"
  user_data           = filebase64("./ecs_ec2_user_data.sh")
  min_size            = 0
  max_size            = 2
  vpc_zone_identifier = module.vpc.public_subnet_ids
  security_group_ids  = [module.instance.public_sg_id]
  load_balancers      = [module.lb.lb_id]

}

module "ecs" {
  source                 = "../Terraform_modules/terraform-aws-ecs"
  env                    = local.env
  auto_scaling_group_arn = module.asg.asg_arn
  execution_role_arn     = "arn:aws:iam::171358186705:role/ecsTaskExecutionRole"
  target_capacity        = 2
  cpu_capacity           = 300
  memory_capacity        = 300
  target_group_arn       = module.lb.target_group_arn
  subnet_ids             = module.vpc.public_subnet_ids
  security_groups        = [module.instance.public_sg_id]
  asg_id                 = module.asg.asg_id
  image_name             = "jainilp12/nginx-assignment:ac780d4dcb19d4d582b83d3bb355e7a9a4684da4"
  container_port         = 80
  network_mode           = "awsvpc"

}

