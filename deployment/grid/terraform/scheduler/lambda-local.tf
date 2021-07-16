module "cancel_tasks" {
  depends_on = [
    kubernetes_service.local_services,
    aws_iam_role_policy_attachment.lambda_logs_attachment,
    aws_cloudwatch_log_group.cancel_tasks_logs
  ]
  source  = "terraform-aws-modules/lambda/aws"
  version = "v1.48.0"
  source_path = [
    "../../../source/control_plane/python/lambda/cancel_tasks",
    {
      path = "../../../source/client/python/api-v0.1/"
      patterns = [
        "!README\\.md",
        "!setup\\.py",
        "!LICENSE*",
      ]
    },
    {
      path = "../../../source/client/python/utils/"
      patterns = [
        "!README\\.md",
        "!setup\\.py",
        "!LICENSE*",
      ]
    },
    {
      pip_requirements = "../../../source/control_plane/python/lambda/cancel_tasks/requirements.txt"
    }
  ]
  function_name = var.lambda_name_cancel_tasks
  build_in_docker = true
  docker_image = "${var.aws_htc_ecr}/lambda-build:build-${var.lambda_runtime}"
  handler = "cancel_tasks.lambda_handler"
  memory_size = 1024
  timeout = 300
  runtime = var.lambda_runtime
#   create_role = false
#   lambda_role = aws_iam_role.role_lambda_cancel_tasks.arn
# 
#   vpc_subnet_ids = var.vpc_private_subnet_ids
#   vpc_security_group_ids = [var.vpc_default_security_group_id]
  use_existing_cloudwatch_log_group = true

  environment_variables  = {
    TASKS_STATUS_TABLE_NAME=aws_dynamodb_table.htc_tasks_status_table.name,
    TASKS_QUEUE_NAME=aws_sqs_queue.htc_task_queue.name,
    TASKS_QUEUE_DLQ_NAME=aws_sqs_queue.htc_task_queue_dlq.name,
    METRICS_ARE_ENABLED=var.metrics_are_enabled,
    METRICS_CANCEL_TASKS_LAMBDA_CONNECTION_STRING=var.metrics_cancel_tasks_lambda_connection_string,
    ERROR_LOG_GROUP=var.error_log_group,
    ERROR_LOGGING_STREAM=var.error_logging_stream,
    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE = var.task_input_passed_via_external_storage,
    GRID_STORAGE_SERVICE = var.grid_storage_service,
    S3_BUCKET = aws_s3_bucket.htc-stdout-bucket.id,
    REDIS_URL = "redis",
    METRICS_GRAFANA_PRIVATE_IP = var.nlb_influxdb, # name of service influxd
    REGION = var.region,
    AWS_DEFAULT_REGION = var.region,
    SQS_PORT = var.local_services_port,
    DYNAMODB_PORT = var.dynamodb_port,
    AWS_ACCESS_KEY_ID = var.access_key,
    AWS_SECRET_ACCESS_KEY = var.secret_key,
  }

   tags = {
    service     = "htc-grid"
  }
  #depends_on = [aws_iam_role_policy_attachment.lambda_logs_attachment, aws_cloudwatch_log_group.cancel_tasks_logs]
}


resource "kubernetes_config_map" "lambda_local" {
  metadata {
    name = "lambda-local"
  }

  data = {
    TASKS_STATUS_TABLE_NAME=aws_dynamodb_table.htc_tasks_status_table.name,
    TASKS_QUEUE_NAME=aws_sqs_queue.htc_task_queue.name,
    TASKS_QUEUE_DLQ_NAME=aws_sqs_queue.htc_task_queue_dlq.name,
    METRICS_ARE_ENABLED=var.metrics_are_enabled,
    METRICS_CANCEL_TASKS_LAMBDA_CONNECTION_STRING=var.metrics_cancel_tasks_lambda_connection_string,
    ERROR_LOG_GROUP=var.error_log_group,
    ERROR_LOGGING_STREAM=var.error_logging_stream,
    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE = var.task_input_passed_via_external_storage,
    GRID_STORAGE_SERVICE = var.grid_storage_service,
    S3_BUCKET = aws_s3_bucket.htc-stdout-bucket.id,
    REDIS_URL = "redis",
    METRICS_GRAFANA_PRIVATE_IP = var.nlb_influxdb, # name of service influxd
    REGION = var.region,
    AWS_DEFAULT_REGION = var.region,
    SQS_PORT = var.local_services_port,
    DYNAMODB_PORT = var.dynamodb_port,
    AWS_ACCESS_KEY_ID = var.access_key,
    AWS_SECRET_ACCESS_KEY = var.secret_key,
    AWS_LAMBDA_FUNCTION_TIMEOUT = var.lambda_timeout,
  }
}


resource "kubernetes_deployment" "cancel_tasks" {
  metadata {
    name      = "cancel-tasks"
    labels = {
      app = "local-scheduler"
      service = "cancel-tasks"
    }
  }
  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "local-scheduler"
        service = "cancel-tasks"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "local-scheduler"
          service = "cancel-tasks"
        }
      }

      spec {
        container {
          image   = var.cancel_tasks_image
          name    = "cancel-tasks"

          resources {
            limits = {
              memory = "1024Mi"
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.lambda_local
              optional = false
            }
          }

          port {
            container_port = var.cancel_tasks_port
          }
        }
      }
    }
  }
  depends_on = [
    kubernetes_service.local_services,
  ]
}