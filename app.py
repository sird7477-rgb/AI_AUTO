from flask import Flask, jsonify, request


def create_app():
    app = Flask(__name__)
    todos = {}
    next_id = 1

    def serialize_todo(todo):
        return {
            "id": todo["id"],
            "title": todo["title"],
            "completed": todo["completed"],
        }

    @app.get("/health")
    def health():
        return jsonify({"status": "ok"})

    @app.get("/")
    def root_health():
        return jsonify({"status": "ok"})

    @app.get("/todos")
    def list_todos():
        return jsonify([serialize_todo(todo) for todo in todos.values()])

    @app.post("/todos")
    def create_todo():
        nonlocal next_id

        data = request.get_json(silent=True) or {}
        title = data.get("title")
        if not isinstance(title, str) or not title.strip():
            return jsonify({"error": "title is required"}), 400

        todo = {
            "id": next_id,
            "title": title.strip(),
            "completed": bool(data.get("completed", False)),
        }
        todos[next_id] = todo
        next_id += 1

        return jsonify(serialize_todo(todo)), 201

    @app.get("/todos/<int:todo_id>")
    def get_todo(todo_id):
        todo = todos.get(todo_id)
        if todo is None:
            return jsonify({"error": "todo not found"}), 404

        return jsonify(serialize_todo(todo))

    @app.patch("/todos/<int:todo_id>")
    def update_todo(todo_id):
        todo = todos.get(todo_id)
        if todo is None:
            return jsonify({"error": "todo not found"}), 404

        data = request.get_json(silent=True) or {}

        if "title" in data:
            title = data["title"]
            if not isinstance(title, str) or not title.strip():
                return jsonify({"error": "title must be a non-empty string"}), 400
            todo["title"] = title.strip()

        if "completed" in data:
            if not isinstance(data["completed"], bool):
                return jsonify({"error": "completed must be a boolean"}), 400
            todo["completed"] = data["completed"]

        return jsonify(serialize_todo(todo))

    @app.delete("/todos/<int:todo_id>")
    def delete_todo(todo_id):
        if todo_id not in todos:
            return jsonify({"error": "todo not found"}), 404

        del todos[todo_id]
        return "", 204

    return app


app = create_app()


if __name__ == "__main__":
    app.run(debug=True)
