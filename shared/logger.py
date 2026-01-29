import logging
import json
from datetime import datetime

def get_logger(name):
    """
    Creates a configured logger for Lambda functionsn hehennnn
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    
    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            json.dumps({
                'name': '%(name)s',
                'level': '%(levelname)s',
                'message': '%(message)s'
            })
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    
    return logger
