import json
import boto3
import os
from botocore.exceptions import ClientError
from botocore.config import Config

# Configure S3 client with regional endpoint and signature version
s3_config = Config(
    signature_version='s3v4',
    s3={'addressing_style': 'virtual'}
)

s3_client = boto3.client('s3', config=s3_config)

BUCKET_NAME = os.environ['BUCKET_NAME']


def lambda_handler(event, context):
    """
    Delete an image from S3.

    Expected path parameters:
    - fileId: The file ID to delete (used as prefix in S3)
    """
    try:
        # Get parameters
        file_id = event.get('pathParameters', {}).get('fileId')

        # Validate required fields
        if not file_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'fileId is required'
                })
            }

        # List objects with the fileId prefix
        response = s3_client.list_objects_v2(
            Bucket=BUCKET_NAME,
            Prefix=f"{file_id}/"
        )

        # Check if file exists
        if 'Contents' not in response or len(response['Contents']) == 0:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'File not found'
                })
            }

        # Delete all objects with this prefix (should typically be just one)
        deleted_keys = []
        for obj in response['Contents']:
            s3_client.delete_object(
                Bucket=BUCKET_NAME,
                Key=obj['Key']
            )
            deleted_keys.append(obj['Key'])

        # Return success response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'File(s) deleted successfully',
                'fileId': file_id,
                'deletedKeys': deleted_keys
            })
        }

    except ClientError as e:
        print(f"AWS Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to delete file',
                'details': str(e)
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }
