"""Shared fixtures for Trading Titans tests."""
import os
import uuid
import pytest
import requests

# Use the public preview URL the frontend uses
BASE_URL = os.environ.get("EXPO_PUBLIC_BACKEND_URL", "https://paper-market-hub.preview.emergentagent.com").rstrip("/")


@pytest.fixture(scope="session")
def base_url():
    return BASE_URL


@pytest.fixture(scope="session")
def api_client():
    s = requests.Session()
    s.headers.update({"Content-Type": "application/json"})
    return s


@pytest.fixture(scope="session")
def test_user(api_client):
    """Register a unique user once per session and return creds + token."""
    email = f"titan_test_{uuid.uuid4().hex[:10]}@example.com"
    password = "TitanTest123"
    name = "Test Titan"
    r = api_client.post(f"{BASE_URL}/api/auth/register",
                        json={"email": email, "password": password, "name": name})
    assert r.status_code == 201, f"register failed: {r.status_code} {r.text}"
    data = r.json()
    return {
        "email": email,
        "password": password,
        "name": name,
        "token": data["access_token"],
        "user": data["user"],
    }


@pytest.fixture(scope="session")
def auth_headers(test_user):
    return {"Authorization": f"Bearer {test_user['token']}", "Content-Type": "application/json"}
