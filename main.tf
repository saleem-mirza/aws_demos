locals {
  timestamp           = timestamp()
  timestamp_sanitized = replace(local.timestamp, "/[- TZ:]/", "")
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ecs_cluster_name" {
  type    = string
  default = "ecs_cluster"
}

variable "service_name" {
  type    = string
  default = "ecs_service"
}

variable "queue_name" {
  type    = string
  default = "s3-object-queue"
}

variable "container_name" {
  type    = string
  default = "demo"
}

variable "container_image" {
  type    = string
  default = "public.ecr.aws/v2k0k1b1/demo:dotnet"
}

resource "aws_default_vpc" "default_vpc" {
  tags = {
    Name = "Default VPC"
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default_vpc.id]
  }
}

data "archive_file" "lambda" {
  type = "zip"
  source {
    content  = templatefile("lambda.tpl", { subnet_id = data.aws_subnets.subnets.ids })
    filename = "lambda.py"
  }

  output_path = "lambda.zip"

}

resource "aws_lambda_function" "ecs_task_runner_lambda" {
  filename      = "lambda.zip"
  function_name = "ecs_task_runner"
  role          = aws_iam_role.lambda_task_runner_role.arn

  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "python3.9"
  handler = "lambda.lambda_handler"
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecs_cluster_name
}

resource "aws_iam_role" "lambda_task_runner_role" {
  name = "lambda_task_runner_role-${var.service_name}"
  inline_policy {
    name = "lambda_task_runner_policy"
    policy = jsonencode(
      {
        "Version" : "2012-10-17",
        "Statement" : [
          {
            "Effect" : "Allow",
            "Action" : "iam:PassRole",
            "Resource" : "*"
          },
          {
            "Effect" : "Allow",
            "Action" : [
              "ecs:RunTask",
              "ecs:StartTask",
              "logs:CreateLogGroup"
            ],
            "Resource" : "*"
          },
          {
            "Effect" : "Allow",
            "Action" : [
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ],
            "Resource" : "*"
          }
        ]
    })
  }
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  ]
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "lambda.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role-${var.service_name}"
  inline_policy {
    name = "ecs_task_role-policy"
    policy = jsonencode(
      {
        "Version" : "2012-10-17",
        "Statement" : [
          {
            "Effect" : "Allow",
            "Action" : [
              "s3:PutObject",
              "s3:GetObject"
            ],
            "Resource" : "${aws_s3_bucket.in_bucket.arn}/*"
          },
          {
            "Effect" : "Allow",
            "Action" : "s3:ListBucket",
            "Resource" : "arn:aws:s3:::*"
          }
        ]
      }
    )
  }
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "ecs-tasks.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role-${var.service_name}"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
  inline_policy {
    name = "ecs_task_execution_policy"
    policy = jsonencode(
      {
        "Version" : "2008-10-17",
        "Statement" : [
          {
            "Effect" : "Allow",
            "Action" : [
              "logs:CreateLogGroup",
              "logs:PutLogEvents"
            ],
            "Resource" : "*"
          },
          {
            "Effect" : "Allow",
            "Action" : "logs:PutLogEvents",
            "Resource" : "*"
          }
        ]
      }
    )
  }
  assume_role_policy = jsonencode(
    {
      "Version" : "2008-10-17",
      "Statement" : [
        {
          "Sid" : "",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "ecs-tasks.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/aws/${var.service_name}"
}

resource "aws_ecs_task_definition" "task_definition" {
  family                   = "ecs_task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 4096
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    # cpu_architecture = "ARM64"
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(
    [
      {
        "name" : var.container_name,
        "image" : var.container_image,
        "essential" : true,
        "logConfiguration" : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-create-group" : "true",
            "awslogs-group" : "/aws/${var.service_name}/ecs_task",
            "awslogs-region" : var.aws_region,
            "awslogs-stream-prefix" : "ecs"
          },
          "requireAttributes" : [
            {
              "name" : "com.amazonaws.ecs.capability.logging-driver.awslogs"
            },
            {
              "name" : "ecs.capability.execution-role-awslogs"
            }
          ]
        }
      }
    ]
  )
}

resource "aws_security_group" "security_group" {
  name   = var.service_name
  vpc_id = aws_default_vpc.default_vpc.id

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
    "0.0.0.0/0"]
  }

  tags = {
    Name = var.service_name
  }
}

resource "aws_sqs_queue" "task_runner_queue" {
  name = "task_runner_queue"
}

resource "aws_sqs_queue_policy" "task_runner_queue_policy" {
  queue_url = aws_sqs_queue.task_runner_queue.url
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "s3.amazonaws.com"
          },
          "Action" : [
            "SQS:SendMessage"
          ],
          "Resource" : aws_sqs_queue.task_runner_queue.arn
        }
      ]
    }
  )
}

resource "aws_lambda_event_source_mapping" "task_queue_lambda_mapping" {
  event_source_arn = aws_sqs_queue.task_runner_queue.arn
  function_name    = aws_lambda_function.ecs_task_runner_lambda.arn
  batch_size       = 1
}

resource "aws_s3_bucket" "in_bucket" {
  bucket        = "bucket-${local.timestamp_sanitized}"
  force_destroy = true
}

resource "aws_s3_bucket_notification" "in_bucket_notification" {
  bucket = aws_s3_bucket.in_bucket.bucket
  queue {
    queue_arn     = aws_sqs_queue.task_runner_queue.arn
    events        = ["s3:ObjectCreated:Put", "s3:ObjectCreated:Post", "s3:ObjectCreated:Copy"]
    filter_prefix = "in/"
  }
}
