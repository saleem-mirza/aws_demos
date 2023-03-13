import json
import boto3
from datetime import datetime
from dateutil import parser

def lambda_handler(event, context):

    subnet_ids = [x for x in "${join(",", subnet_id)}".split(",")]

    event_body = json.loads(event["Records"][0]["body"])
    if event_body.get('Event') == 's3:TestEvent':
        return "TestEvent"

    event_body = event_body["Records"][0]
    s3_event = event_body["s3"]
    s3_bucket = s3_event["bucket"]["name"]
    s3_object_key = s3_event["object"]["key"]

    s3_object_timestamp = "{}".format(
        datetime.timestamp(
            parser.parse(event_body["eventTime"])
        )).replace(".", "_")

    client = boto3.client("ecs")
    response = client.run_task(
        cluster="ecs_cluster",  # name of the cluster
        launchType="FARGATE",
        # replace with your task definition name and revision
        taskDefinition="ecs_task",
        count=1,
        platformVersion="LATEST",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": subnet_ids,
                "assignPublicIp": "ENABLED"
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": "demo",
                    "environment": [
                        {
                            "name": "s3_bucket",
                            "value": s3_bucket
                        },
                        {
                            "name": "s3_object_key",
                            "value": s3_object_key
                        },
                        {
                            "name": "event_time",
                            "value": "{}".format(s3_object_timestamp)
                        }
                    ]
                }
            ]
        }
    )
    return str(response)
