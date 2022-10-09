import boto3
import json

def view_items():
    client= boto3.client('dynamodb')
    
    response= client.get_item(
       TableName= 'VisitorCounterDB',
       Key= {
           'Version': {
               'N': '1'
           }
       },
       ProjectionExpression= 'TotalCount'
        )
        
    for Item in response:
       return response['Item']['TotalCount']
    


def dynamo_action():
    client = boto3.client('dynamodb')

    client.update_item(
        TableName='VisitorCounterDB',
        Key= { 
            'Version': { 
                'N': '1'
            }
        },
        UpdateExpression="SET TotalCount = TotalCount + :v",
        ExpressionAttributeValues={
            ':v': { 'N': '1'}
        },
        ReturnValues="UPDATED_NEW"
    )
    

def update(event, context):
    dynamo_action()
    return view_items()