import pytest

from app import create_app


@pytest.fixture()
def client(tmp_path):
    app = create_app(tmp_path / "todos.sqlite3")
    app.config.update(TESTING=True)

    return app.test_client()


@pytest.fixture()
def existing_todo(client):
    response = client.post("/todos", json={"title": "Test todo"})

    assert response.status_code == 201
    return response.get_json()


def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_create_and_list_todos(client):
    create_response = client.post("/todos", json={"title": "Buy milk"})

    assert create_response.status_code == 201
    created_todo = create_response.get_json()
    todo_id = created_todo["id"]
    assert created_todo == {
        "id": todo_id,
        "title": "Buy milk",
        "completed": False,
    }

    list_response = client.get("/todos")
    assert list_response.status_code == 200
    assert list_response.get_json() == [
        {"id": todo_id, "title": "Buy milk", "completed": False}
    ]


def test_todos_persist_across_app_instances(tmp_path):
    db_path = tmp_path / "todos.sqlite3"
    first_app = create_app(db_path)
    first_app.config.update(TESTING=True)
    first_client = first_app.test_client()

    create_response = first_client.post("/todos", json={"title": "Persist me"})
    assert create_response.status_code == 201

    second_app = create_app(db_path)
    second_app.config.update(TESTING=True)
    second_client = second_app.test_client()

    list_response = second_client.get("/todos")
    assert list_response.status_code == 200
    assert list_response.get_json() == [
        {
            "id": create_response.get_json()["id"],
            "title": "Persist me",
            "completed": False,
        }
    ]


def test_create_todo_requires_title(client):
    response = client.post("/todos", json={"title": "   "})

    assert response.status_code == 400
    assert "error" in response.get_json()


def test_get_unknown_todo_returns_404(client):
    response = client.get("/todos/999")

    assert response.status_code == 404
    assert "error" in response.get_json()


def test_update_todo(client, existing_todo):
    todo_id = existing_todo["id"]

    response = client.patch(
        f"/todos/{todo_id}",
        json={"title": "Write Flask tests", "completed": True},
    )

    assert response.status_code == 200
    assert response.get_json() == {
        "id": todo_id,
        "title": "Write Flask tests",
        "completed": True,
    }


def test_update_rejects_invalid_completed(client, existing_todo):
    todo_id = existing_todo["id"]

    response = client.patch(f"/todos/{todo_id}", json={"completed": "yes"})

    assert response.status_code == 400
    assert "error" in response.get_json()


def test_delete_todo(client, existing_todo):
    todo_id = existing_todo["id"]

    delete_response = client.delete(f"/todos/{todo_id}")
    assert delete_response.status_code == 204

    get_response = client.get(f"/todos/{todo_id}")
    assert get_response.status_code == 404


def test_delete_unknown_todo_returns_404(client):
    response = client.delete("/todos/999")

    assert response.status_code == 404
    assert "error" in response.get_json()
