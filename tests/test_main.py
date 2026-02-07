from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    payload = response.json()
    assert payload["message"].startswith("hello from")
    assert "tenant" in payload


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert "tenant" in payload


def test_metrics():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text


def test_fail_endpoint_disabled_by_default(monkeypatch):
    monkeypatch.delenv("ENABLE_DEMO_FAILURE_ENDPOINT", raising=False)
    response = client.get("/fail")
    assert response.status_code == 404


def test_fail_endpoint_enabled(monkeypatch):
    monkeypatch.setenv("ENABLE_DEMO_FAILURE_ENDPOINT", "true")
    response = client.get("/fail?code=503")
    assert response.status_code == 503
