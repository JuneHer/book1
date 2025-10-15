# 1. Provider 선언
provider "aws" {
  region = var.aws_region
}

# Backend 설정
terraform {
  backend "s3" {
    bucket         = "terraform-state-juneher-1760513019"
    key            = "terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
  }
}
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-public-subnet"
  }
}



resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-2a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-2b"
}







resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-igw"
  }
}
 
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "terraform-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}
 

 resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "terraform-web-sg"

  # SSH 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 학습 목적이므로 전 세계 허용
  }

  # HTTP 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-web-sg"
  }
}


# 2. Resource 선언 (EC2 인스턴스)
resource "aws_instance" "example" {
  ami           = "ami-0c9c942bd7bf113a2" # Ubuntu 20.04 LTS
  instance_type = var.instance_type
  key_name      = "terraform-key"          # AWS 콘솔에서 만든 키 이름
  subnet_id              = aws_subnet.public.id              # ✅ 추가
  vpc_security_group_ids = [aws_security_group.web_sg.id]    # ✅ 이미 추가한 부분


  tags = {
    Name = "terraform-example"
  }
}

# 3. Variable 정의
variable "aws_region" {
  description = "AWS 리전"
  default     = "ap-northeast-2"
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  default     = "t2.micro"
}


resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id
  name   = "terraform-rds-sg"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "terraform-rds-sg" }
}

resource "aws_db_subnet_group" "rds_subnet" {
  name       = "terraform-rds-subnet-${random_id.db_subnet_group_suffix.hex}"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "terraform-rds-subnet-${random_id.db_subnet_group_suffix.hex}"
  }
}

resource "random_id" "db_subnet_group_suffix" {
  byte_length = 4
}


resource "aws_db_instance" "mysql" {
  identifier        = "terraform-mysql-${random_id.db_subnet_group_suffix.hex}"
  allocated_storage = 20
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  username          = "admin"
  password          = "password1234"   # 실제로는 Secrets Manager 권장
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  tags = { Name = "terraform-mysql-${random_id.db_subnet_group_suffix.hex}" }
}

# Output 정의
output "instance_ip" {
  description = "EC2 인스턴스의 퍼블릭 IP"
  value       = aws_instance.example.public_ip
}