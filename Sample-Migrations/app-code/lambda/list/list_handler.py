import json
import boto3
import os
from botocore.exceptions import ClientError

s3_client = boto3.client('s3')

BUCKET_NAME = os.environ['BUCKET_NAME']
URL_EXPIRATION = int(os.environ.get('URL_EXPIRATION', 3600))


def lambda_handler(event, context):
    """
    List all files in the S3 bucket with pre-signed view URLs.

    Query Parameters:
    - prefix: (optional) Filter objects by prefix
    - maxKeys: (optional) Maximum number of items to return (default: 50)
    """
    try:
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        prefix = query_params.get('prefix', '')
        max_keys = int(query_params.get('maxKeys', 50))

        # List objects in S3
        list_params = {
            'Bucket': BUCKET_NAME,
            'MaxKeys': max_keys
        }
        if prefix:
            list_params['Prefix'] = prefix

        response = s3_client.list_objects_v2(**list_params)

        if 'Contents' not in response:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'files': [],
                    'count': 0
                })
            }

        # Generate pre-signed URLs and collect metadata
        files = []
        for obj in response.get('Contents', []):
            s3_key = obj['Key']

            # Skip if it's a folder marker
            if s3_key.endswith('/'):
                continue

            try:
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
                file_name = metadata.get('originalfilename', s3_key.split('/')[-1])

                # Get object tags
                tags = []
                try:
                    tag_response = s3_client.get_object_tagging(
                        Bucket=BUCKET_NAME,
                        Key=s3_key
                    )
                    tags = [tag['Value'] for tag in tag_response.get('TagSet', [])]
                except ClientError:
                    pass  # Tags might not exist

                file_info = {
                    'fileId': s3_key.split('/')[0] if '/' in s3_key else s3_key,
                    's3Key': s3_key,
                    'fileName': file_name,
                    'fileType': head_response.get('ContentType', 'unknown'),
                    'size': obj['Size'],
                    'lastModified': obj['LastModified'].isoformat(),
                    'uploadDate': metadata.get('uploaddate', obj['LastModified'].isoformat()),
                    'description': metadata.get('description', ''),
                    'tags': tags,
                    'viewUrl': view_url,
                    'urlExpiresIn': URL_EXPIRATION
                }
                files.append(file_info)

            except ClientError as e:
                print(f"Error processing file {s3_key}: {str(e)}")
                continue

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'files': files,
                'count': len(files),
                'isTruncated': response.get('IsTruncated', False)
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
                'error': 'Failed to retrieve files',
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
