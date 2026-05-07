import sqlite3
from pathlib import Path


class TodoRepository:
    def __init__(self, db_path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _connect(self):
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init_db(self):
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS todos (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    completed INTEGER NOT NULL DEFAULT 0
                )
                """
            )

    def _row_to_todo(self, row):
        if row is None:
            return None

        return {
            "id": row["id"],
            "title": row["title"],
            "completed": bool(row["completed"]),
        }

    def list(self):
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT id, title, completed FROM todos ORDER BY id"
            ).fetchall()

        return [self._row_to_todo(row) for row in rows]

    def create(self, title, completed=False):
        with self._connect() as connection:
            cursor = connection.execute(
                "INSERT INTO todos (title, completed) VALUES (?, ?)",
                (title, int(completed)),
            )
            row = connection.execute(
                "SELECT id, title, completed FROM todos WHERE id = ?",
                (cursor.lastrowid,),
            ).fetchone()

        return self._row_to_todo(row)

    def get(self, todo_id):
        with self._connect() as connection:
            row = connection.execute(
                "SELECT id, title, completed FROM todos WHERE id = ?",
                (todo_id,),
            ).fetchone()

        return self._row_to_todo(row)

    def update(self, todo_id, title=None, completed=None):
        todo = self.get(todo_id)
        if todo is None:
            return None

        next_title = title if title is not None else todo["title"]
        next_completed = completed if completed is not None else todo["completed"]

        with self._connect() as connection:
            connection.execute(
                "UPDATE todos SET title = ?, completed = ? WHERE id = ?",
                (next_title, int(next_completed), todo_id),
            )

        return self.get(todo_id)

    def delete(self, todo_id):
        with self._connect() as connection:
            cursor = connection.execute("DELETE FROM todos WHERE id = ?", (todo_id,))

        return cursor.rowcount > 0
