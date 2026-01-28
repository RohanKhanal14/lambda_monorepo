import json
import requests
from logger import get_logger

logger = get_logger(__name__)

def lambda_handler(event, context):
    logger.info("Lambda 1 invoked")
    logger.info(f"Event: {json.dumps(event)}")
    response = requests.get("https://httpbin.org/get", timeout=3)

    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello from test for webhook! this si branch tt',
            'http_status': response.status_code,
            'lambda': 'lambda1'
        })
    }

