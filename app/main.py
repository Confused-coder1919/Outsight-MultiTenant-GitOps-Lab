import logging
import os
import time

from fastapi import FastAPI, HTTPException, Query, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_NAME = os.getenv("APP_NAME", "demo-api")
TENANT_NAME = os.getenv("TENANT_NAME", "unknown")

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(APP_NAME)

app = FastAPI(title=APP_NAME)

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status", "tenant", "app"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path", "tenant", "app"],
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    path = request.url.path
    status = str(response.status_code)

    REQUEST_COUNT.labels(request.method, path, status, TENANT_NAME, APP_NAME).inc()
    REQUEST_LATENCY.labels(request.method, path, TENANT_NAME, APP_NAME).observe(duration)

    logger.info("request path=%s status=%s tenant=%s", path, status, TENANT_NAME)
    return response


@app.get("/")
def root():
    return {"message": f"hello from {APP_NAME}", "tenant": TENANT_NAME}


@app.get("/health")
def health():
    return {"status": "ok", "tenant": TENANT_NAME}


@app.get("/metrics")
def metrics():
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)


@app.get("/fail")
def fail(code: int = Query(default=500, ge=400, le=599)):
    # Keep failure injection disabled by default so normal environments are safe.
    enabled = os.getenv("ENABLE_DEMO_FAILURE_ENDPOINT", "false").lower() == "true"
    if not enabled:
        raise HTTPException(status_code=404, detail="Not found")
    raise HTTPException(status_code=code, detail=f"demo failure endpoint ({code})")
