import os
import json
import hmac
import hashlib
import base64
import logging
import boto3
import uuid
from urllib.parse import parse_qs
from urllib.request import Request, urlopen

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codepipeline = boto3.client('codepipeline')

def _get_raw_body(event: dict) -> bytes:
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        return base64.b64decode(body)
    return body.encode("utf-8")

def _get_header(headers: dict, name: str) -> str | None:
    return headers.get(name) or headers.get(name.lower()) or headers.get(name.upper())

def _verify_github_signature(headers: dict, raw_body: bytes, secret: str) -> bool:
    sig256 = _get_header(headers, "X-Hub-Signature-256")
    if not sig256 or not sig256.startswith("sha256="):
        return False

    expected = "sha256=" + hmac.new(
        secret.encode("utf-8"),
        raw_body,
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(expected, sig256)

def _parse_payload(headers: dict, raw_body: bytes) -> dict:
    content_type = (_get_header(headers, "Content-Type") or "").split(";")[0].strip().lower()
    body_text = raw_body.decode("utf-8", errors="replace")

    if content_type == "application/json":
        return json.loads(body_text)

    if content_type == "application/x-www-form-urlencoded":
        form = parse_qs(body_text, keep_blank_values=True)
        if "payload" in form and form["payload"]:
            return json.loads(form["payload"][0])
        raise ValueError("Form-encoded webhook missing 'payload' field")

    # fallback: try json, then form
    try:
        return json.loads(body_text)
    except Exception:
        form = parse_qs(body_text, keep_blank_values=True)
        if "payload" in form and form["payload"]:
            return json.loads(form["payload"][0])
        raise

def _changed_files_from_push_payload(payload: dict) -> list[str]:
    """
    Collect unique changed files from webhook payload.
    GitHub push payload includes commits[].{added,modified,removed}.
    """
    files = set()
    for c in payload.get("commits", []) or []:
        for k in ("added", "modified", "removed"):
            for p in c.get(k, []) or []:
                files.add(p)
    return sorted(files)

def _determine_pipelines_to_trigger(changed_files: list[str]) -> list[str]:
    """
    Determine which pipelines to trigger based on changed files.
    
    Logic:
    - lambda1/* changed → trigger lambda1-pipeline only
    - lambda2/* changed → trigger lambda2-pipeline only
    - layers/shared/* changed → trigger BOTH pipelines (shared dependency)
    """
    pipelines = set()
    shared_changed = any('layers/shared/' in f for f in changed_files)
    
    if shared_changed or any('lambda1/' in f for f in changed_files):
        pipelines.add('lambda1-pipeline')
    
    if shared_changed or any('lambda2/' in f for f in changed_files):
        pipelines.add('lambda2-pipeline')
    
    return list(pipelines)

def _trigger_pipeline(pipeline_name: str) -> dict:
    """
    Trigger a CodePipeline execution.
    Returns the execution ID if successful.
    """
    try:
        response = codepipeline.start_pipeline_execution(
            name=pipeline_name,
            clientRequestToken=str(uuid.uuid4())
        )
        logger.info(f"Successfully triggered pipeline: {pipeline_name}, executionId: {response['pipelineExecutionId']}")
        return {
            'success': True,
            'pipeline': pipeline_name,
            'executionId': response['pipelineExecutionId']
        }
    except Exception as e:
        logger.exception(f"Failed to trigger pipeline {pipeline_name}: {str(e)}")
        return {
            'success': False,
            'pipeline': pipeline_name,
            'error': str(e)
        }

def lambda_handler(event, context):
    headers = event.get("headers") or {}
    raw_body = _get_raw_body(event)

    # Log request metadata
    logger.info(f"route={event.get('requestContext', {}).get('http', {}).get('method')} "
                f"path={event.get('rawPath')} body_len={len(raw_body)} "
                f"content-type={_get_header(headers, 'Content-Type')}")

    # Verify GitHub webhook signature
    secret = os.environ.get("GITHUB_WEBHOOK_SECRET", "")
    if not secret:
        logger.error("Missing env var GITHUB_WEBHOOK_SECRET")
        return {"statusCode": 500, "body": json.dumps({"error": "Server misconfigured"})}

    if not _verify_github_signature(headers, raw_body, secret):
        logger.warning("Signature verification failed")
        return {"statusCode": 401, "body": json.dumps({"error": "Invalid signature"})}

    # Parse payload
    try:
        payload = _parse_payload(headers, raw_body)
    except Exception as e:
        logger.exception(f"Invalid payload parse: {str(e)}")
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid payload"})}

    event_type = _get_header(headers, "X-GitHub-Event") or "unknown"
    delivery = _get_header(headers, "X-GitHub-Delivery") or "unknown"
    logger.info(f"github_event={event_type} delivery={delivery}")

    # Handle ping event
    if event_type == "ping":
        return {"statusCode": 200, "body": json.dumps({"message": "pong"})}

    # Only process push events
    if event_type != "push":
        logger.info(f"Ignoring non-push event: {event_type}")
        return {"statusCode": 200, "body": json.dumps({"message": f"event {event_type} received"})}

    # Extract push event details
    repo = payload.get("repository", {}).get("full_name")
    before = payload.get("before")
    after = payload.get("after")
    ref = payload.get("ref")

    # Get changed files from payload
    changed_files = _changed_files_from_push_payload(payload)
    logger.info(f"push repo={repo} ref={ref} before={before} after={after} "
                f"changed_files_count={len(changed_files)}")
    logger.info(f"changed_files_sample={changed_files[:50]}")

    # Determine which pipelines to trigger
    pipelines_to_trigger = _determine_pipelines_to_trigger(changed_files)
    logger.info(f"Determined pipelines to trigger: {pipelines_to_trigger}")

    # Trigger pipelines
    triggered_results = []
    for pipeline_name in pipelines_to_trigger:
        result = _trigger_pipeline(pipeline_name)
        triggered_results.append(result)

    # Prepare response
    response_body = {
        "repo": repo,
        "ref": ref,
        "before": before,
        "after": after,
        "changed_files_count": len(changed_files),
        "changed_files": changed_files[:50],
        "pipelines_triggered": pipelines_to_trigger,
        "trigger_results": triggered_results
    }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(response_body)
    }
