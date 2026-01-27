import json
from logger import get_logger

logger = get_logger(__name__)

def lambda_handler(event, context):
    logger.info("Lambda 1 invoked")
    logger.info(f"Event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello from test for webhook! this si branch test | pipeline triggure test',
            
            'lambda': 'lambda1'
        })
    }

