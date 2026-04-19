import json
import boto3
import os
from botocore.exceptions import ClientError

s3_client = boto3.client('s3')

BUCKET_NAME = os.environ['BUCKET_NAME']
URL_EXPIRATION = int(os.environ.get('URL_EXPIRATION', 3600))


def lambda_handler(event, context):
    """
    Generate a pre-signed URL for viewing a specific file.

    Path Parameters:
    - fileId: The file ID (used as prefix in S3 key)

    Note: This simplified version lists objects with the fileId prefix
    and generates a presigned URL for the first match.
    """
    try:
        # Get path parameters
        path_params = event.get('pathParameters') or {}
        file_id = path_params.get('fileId')

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
            Prefix=f"{file_id}/",
            MaxKeys=1
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

        s3_key = response['Contents'][0]['Key']

        # Get object metadata
        head_response = s3_client.head_object(
            Bucket=BUCKET_NAME,
            Key=s3_key
        )

        # Generate pre-signed URL for viewing
        view_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': s3_key
            },
            ExpiresIn=URL_EXPIRATION
        )

        # Extract metadata
        metadata = head_response.get('Metadata', {})

        # Return response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'fileId': file_id,
                's3Key': s3_key,
                'fileName': metadata.get('originalfilename', s3_key.split('/')[-1]),
                'fileType': head_response.get('ContentType', 'unknown'),
                'description': metadata.get('description', ''),
                'uploadDate': metadata.get('uploaddate', response['Contents'][0]['LastModified'].isoformat()),
                'size': response['Contents'][0]['Size'],
                'viewUrl': view_url,
                'expiresIn': URL_EXPIRATION
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
                'error': 'Failed to generate view URL',
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
