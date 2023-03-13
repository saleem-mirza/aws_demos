import boto3
import os

s3_bucket = os.environ['s3_bucket']
s3_object_key = os.environ['s3_object_key']
if s3_bucket == "" or s3_object_key == "":
    exit()

s3_client = boto3.client('s3')
s3_client.copy({
    'Bucket': s3_bucket,
    'Key': s3_object_key
}, s3_bucket, 'processed/{}_{}'.format(os.environ['event_time'], s3_object_key.split('/').pop()))
