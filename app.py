from flask import Flask, jsonify, request

from repository import TodoRepository


def create_app(db_path="instance/todos.sqlite3"):
    app = Flask(__name__)
    repository = TodoRepository(db_path)

    def serialize_todo(todo):
        return {
            "id": todo["id"],
            "title": todo["title"],
            "completed": todo["completed"],
        }

    @app.get("/")
    def root():
        return jsonify({"status": "ok"})

    @app.get("/health")
    def health():
        return jsonify({"status": "ok"})

    @app.get("/todos")
    def list_todos():
        return jsonify([serialize_todo(todo) for todo in repository.list()])

    @app.post("/todos")
    def create_todo():
        data = request.get_json(silent=True) or {}
        title = data.get("title")
        if not isinstance(title, str) or not title.strip():
            return jsonify({"error": "title is required"}), 400

        todo = repository.create(title.strip(), bool(data.get("completed", False)))

        return jsonify(serialize_todo(todo)), 201

    @app.get("/todos/<int:todo_id>")
    def get_todo(todo_id):
        todo = repository.get(todo_id)
        if todo is None:
            return jsonify({"error": "todo not found"}), 404

        return jsonify(serialize_todo(todo))

    @app.patch("/todos/<int:todo_id>")
    def update_todo(todo_id):
        todo = repository.get(todo_id)
        if todo is None:
            return jsonify({"error": "todo not found"}), 404

        data = request.get_json(silent=True) or {}
        title = None
        completed = None

        if "title" in data:
            title = data["title"]
            if not isinstance(title, str) or not title.strip():
                return jsonify({"error": "title must be a non-empty string"}), 400
            title = title.strip()

        if "completed" in data:
            if not isinstance(data["completed"], bool):
                return jsonify({"error": "completed must be a boolean"}), 400
            completed = data["completed"]

        return jsonify(serialize_todo(repository.update(todo_id, title, completed)))

    @app.delete("/todos/<int:todo_id>")
    def delete_todo(todo_id):
        if not repository.delete(todo_id):
            return jsonify({"error": "todo not found"}), 404

        return "", 204

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(debug=True)
