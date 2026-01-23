from datetime import datetime

def get_timestamp():
    """Return current timestamp in ISO format"""
    return datetime.utcnow().isoformat()

def format_response(status_code, body):
    """Format standard API Gateway response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': body
    }
