import json
from logger import get_logger

logger = get_logger(__name__)

def lambda_handler(event, context):
    logger.info("Lambda 2 invoked")
    logger.info(f"Event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello from Lambda multi test! tyesting for lambda2sss',
            'lambda': 'lambda2'
        })
    }
