import json
import boto3
import os

# Initialize the DynamoDB resource and table
dynamo_db = boto3.resource('dynamodb')
ddb_table_name = os.environ['TABLE_NAME']
table = dynamo_db.Table(ddb_table_name)

def lambda_handler(event, context):
    # Define the key used to identify the counter row
    key = {'id': 'visitor_count_id'}

    try:
        # Try to get the current visitor count
        response = table.get_item(Key=key)
        item = response.get("Item")

        if not item:
            # Initialize count if not present
            count = 0
        else:
            count = int(item.get("visitor_count", 0))

        # Increment the count
        new_count = count + 1

        # Update the item in DynamoDB
        table.update_item(
            Key=key,
            UpdateExpression='SET visitor_count = :c',
            ExpressionAttributeValues={':c': new_count},
            ReturnValues='UPDATED_NEW'
        )

        # Return the new count
        return {
            'statusCode': 200,
            'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': 'https://thomaskjohn.com',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET',
            'Content-Type': 'application/json'
        },
            'body': json.dumps({'Count': new_count})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Origin': 'https://thomaskjohn.com',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': str(e)})
        }
