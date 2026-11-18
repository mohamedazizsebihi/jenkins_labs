import pytest

from app import add, app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_add():
    assert add(2, 3) == 5


def test_index(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.get_json()["message"] == "Hello Jenkins"


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "up"}


def test_add_route(client):
    response = client.get("/add/4/6")
    assert response.get_json() == {"result": 10}


def test_index_version(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "42")
    assert client.get("/").get_json()["version"] == "42"
