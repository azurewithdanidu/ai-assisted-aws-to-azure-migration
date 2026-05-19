import json
import boto3
import os
import uuid
from datetime import datetime
from botocore.exceptions import ClientError
from botocore.config import Config

# Configure S3 client with regional endpoint and signature version
s3_config = Config(
    signature_version='s3v4',
    s3={'addressing_style': 'virtual'}
)

s3_client = boto3.client('s3', config=s3_config)

BUCKET_NAME = os.environ['BUCKET_NAME']
URL_EXPIRATION = int(os.environ.get('URL_EXPIRATION', 3600))


def lambda_handler(event, context):
    """
    Generate a pre-signed URL for uploading an image to S3.
    Metadata is stored as S3 object tags and custom metadata.

    Expected request body:
    {
        "fileName": "image.jpg",
        "fileType": "image/jpeg",
        "description": "Optional description"
    }
    """
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))

        file_name = body.get('fileName')
        file_type = body.get('fileType', 'image/jpeg')
        description = body.get('description', '')
        tags = body.get('tags', [])

        # Validate required fields
        if not file_name:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'fileName is required'
                })
            }

        # Generate unique file ID
        file_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()

        # Create S3 key
        s3_key = f"{file_id}/{file_name}"

        # Prepare metadata
        metadata = {
            'uploaddate': timestamp,
            'originalfilename': file_name
        }
        if description:
            metadata['description'] = description

        # Generate pre-signed POST for upload
        # Build fields and conditions for metadata
        fields = {
            'Content-Type': file_type,
            **{f'x-amz-meta-{k}': v for k, v in metadata.items()}
        }

        conditions = [
            {'Content-Type': file_type},
            ['content-length-range', 0, 10485760]  # Max 10MB
        ]

        # Add condition for each metadata field
        for key, value in metadata.items():
            conditions.append({f'x-amz-meta-{key}': value})

        # Add tags if provided (using x-amz-tagging)
        if tags:
            # Convert tags array to URL-encoded key-value pairs
            tag_string = '&'.join([f'tag{i}={tag}' for i, tag in enumerate(tags)])
            fields['x-amz-tagging'] = tag_string
            conditions.append({'x-amz-tagging': tag_string})

        presigned_post = s3_client.generate_presigned_post(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Fields=fields,
            Conditions=conditions,
            ExpiresIn=URL_EXPIRATION
        )

        # Return response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'uploadUrl': presigned_post['url'],
                'uploadFields': presigned_post['fields'],
                'fileId': file_id,
                's3Key': s3_key,
                'expiresIn': URL_EXPIRATION,
                'message': 'Use POST method to upload the file to the provided URL with the given fields'
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
                'error': 'Failed to generate upload URL',
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
