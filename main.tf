 terraform {
  backend "s3" {
  bucket         = "task16-wordpress-tfstate"
  key            = "task16/wordpress/terraform.tfstate"
  region         = "us-east-1"
   encrypt        = true
  }
 }

resource "aws_vpc" "task16_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "task16-vpc"
  }
}

resource "aws_internet_gateway" "task16_igw" {
  vpc_id = aws_vpc.task16_vpc.id

  tags = {
    Name = "task16-igw"
  }
}

resource "aws_route_table" "task16_public_rt" {
  vpc_id = aws_vpc.task16_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.task16_igw.id
  }

  tags = {
    Name = "task16-public-rt"
  }
}

resource "aws_subnet" "task16_jump_subnet" {
  vpc_id                  = aws_vpc.task16_vpc.id
  cidr_block              = var.jump_subnet_cidr
  availability_zone       = var.primary_availability_zone2
  map_public_ip_on_launch = true

  tags = {
    Name = "task16-jump-subnet"
  }
}

resource "aws_route_table_association" "task16_jump_assoc" {
  subnet_id      = aws_subnet.task16_jump_subnet.id
  route_table_id = aws_route_table.task16_public_rt.id
}

resource "aws_subnet" "task16_public_subnet" {
  vpc_id                  = aws_vpc.task16_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.primary_availability_zone1
  map_public_ip_on_launch = true

  tags = {
    Name = "task16-public-subnet"
  }
}

resource "aws_route_table_association" "task16_public_assoc" {
  subnet_id      = aws_subnet.task16_public_subnet.id
  route_table_id = aws_route_table.task16_public_rt.id
}

resource "aws_subnet" "task16_private_subnet1" {
  vpc_id            = aws_vpc.task16_vpc.id
  cidr_block        = var.private_subnet1_cidr
  availability_zone = var.primary_availability_zone1

  tags = {
    Name = "task16-private-subnet-1"
  }
}

resource "aws_subnet" "task16_private_subnet2" {
  vpc_id            = aws_vpc.task16_vpc.id
  cidr_block        = var.private_subnet2_cidr
  availability_zone = var.primary_availability_zone2

  tags = {
    Name = "task16-private-subnet-2"
  }
}

resource "aws_db_subnet_group" "task16_db_subnets" {
  name       = "task16-db-subnet-group"
  subnet_ids = [
    aws_subnet.task16_private_subnet1.id,
    aws_subnet.task16_private_subnet2.id
  ]

  tags = {
    Name = "task16-db-subnet-group"
  }
}

resource "aws_security_group" "task16_db_sg" {
  name        = "task16-db-sg"
  description = "Allow MySQL access from the WordPress EC2 instance"
  vpc_id      = aws_vpc.task16_vpc.id

  ingress {
    description     = "MySQL access from WordPress EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.task16_ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "task16_wordpress_db" {
  identifier              = "task16-wordpress-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "wordpressdb"
  username                = var.db_username
  password                = var.db_password
  parameter_group_name    = "default.mysql8.0"
  db_subnet_group_name    = aws_db_subnet_group.task16_db_subnets.name
  vpc_security_group_ids  = [aws_security_group.task16_db_sg.id]
  skip_final_snapshot     = true

  tags = {
    Name = "task16-wordpress-db"
  }
}

resource "aws_security_group" "task16_ec2_sg" {
  name   = "task16-ec2-sg"
  vpc_id = aws_vpc.task16_vpc.id

  ingress {
    description = "Allow HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH access from jump subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.jump_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "task16_wordpress_ec2" {
  ami                    = var.base_ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.task16_public_subnet.id
  vpc_security_group_ids = [aws_security_group.task16_ec2_sg.id]
  user_data = templatefile("${path.module}/wp_userdata.sh.tpl", {
    db_username   = var.db_username,
    db_password   = var.db_password,
    db_host       = aws_db_instance.task16_wordpress_db.address,
    sns_topic_arn = aws_sns_topic.task16_wordpress_sns.arn,
    region        = var.region
  })
  tags = {
    Name = "task16-wordpress-ec2"
  }
}

resource "aws_ami_from_instance" "task16_wp_ami" {
  name               = "task16-wordpress-ami"
  source_instance_id = aws_instance.task16_wordpress_ec2.id
  depends_on         = [aws_instance.task16_wordpress_ec2]
}

resource "aws_lb" "task16_alb" {
  name               = "task16-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.task16_ec2_sg.id]
  subnets            = [
    aws_subnet.task16_public_subnet.id,
    aws_subnet.task16_jump_subnet.id
  ]
  tags = {
    Name = "task16-alb"
  }
}

resource "aws_lb_target_group" "task16_alb_tg" {
  name     = "task16-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.task16_vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name = "task16-alb-tg"
  }
}

resource "aws_lb_listener" "task16_alb_listener" {
  load_balancer_arn = aws_lb.task16_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.task16_alb_tg.arn
  }
}

resource "aws_launch_template" "task16_lt" {
  name_prefix   = "task16-wordpress-lt-"
  image_id      = aws_ami_from_instance.task16_wp_ami.id
  instance_type = "t2.micro"
  user_data     = base64encode(templatefile("${path.module}/wp_userdata.sh.tpl", {
                    db_username   = var.db_username,
                    db_password   = var.db_password,
                    db_host       = aws_db_instance.task16_wordpress_db.address,
                    sns_topic_arn = aws_sns_topic.task16_wordpress_sns.arn,
                    region        = var.region
                  }))
  vpc_security_group_ids = [aws_security_group.task16_ec2_sg.id]
}

resource "aws_autoscaling_group" "task16_asg" {
  name                = "task16-asg"
  min_size            = 1
  max_size            = 3
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = [aws_subnet.task16_public_subnet.id]
  target_group_arns   = [aws_lb_target_group.task16_alb_tg.arn]
  launch_template {
    id      = aws_launch_template.task16_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "task16-wordpress-asg"
    propagate_at_launch = true
  }
}

resource "aws_sns_topic" "task16_wordpress_sns" {
  name = "task16-wordpress-sns"
}

resource "aws_sns_topic_subscription" "task16_wordpress_sns_subscription" {
  topic_arn = aws_sns_topic.task16_wordpress_sns.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

