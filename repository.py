import sqlite3
from pathlib import Path


class TodoRepository:
    def __init__(self, database_url):
        self.database_url = str(database_url)
        self.is_postgres = self.database_url.startswith(
            ("postgres://", "postgresql://")
        )

        if not self.is_postgres:
            self.db_path = Path(database_url)
            self.db_path.parent.mkdir(parents=True, exist_ok=True)

        self._init_db()

    def _connect(self):
        if self.is_postgres:
            import psycopg
            from psycopg.rows import dict_row

            return psycopg.connect(self.database_url, row_factory=dict_row)

        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init_db(self):
        if self.is_postgres:
            create_table_sql = """
                CREATE TABLE IF NOT EXISTS todos (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    completed BOOLEAN NOT NULL DEFAULT FALSE
                )
                """
        else:
            create_table_sql = """
                CREATE TABLE IF NOT EXISTS todos (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    completed INTEGER NOT NULL DEFAULT 0
                )
                """

        with self._connect() as connection:
            connection.execute(create_table_sql)

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
            if self.is_postgres:
                row = connection.execute(
                    """
                    INSERT INTO todos (title, completed)
                    VALUES (%s, %s)
                    RETURNING id, title, completed
                    """,
                    (title, completed),
                ).fetchone()
                return self._row_to_todo(row)

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
            placeholder = "%s" if self.is_postgres else "?"
            row = connection.execute(
                f"SELECT id, title, completed FROM todos WHERE id = {placeholder}",
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
            if self.is_postgres:
                connection.execute(
                    "UPDATE todos SET title = %s, completed = %s WHERE id = %s",
                    (next_title, next_completed, todo_id),
                )
                return self.get(todo_id)

            connection.execute(
                "UPDATE todos SET title = ?, completed = ? WHERE id = ?",
                (next_title, int(next_completed), todo_id),
            )

        return self.get(todo_id)

    def delete(self, todo_id):
        with self._connect() as connection:
            placeholder = "%s" if self.is_postgres else "?"
            cursor = connection.execute(
                f"DELETE FROM todos WHERE id = {placeholder}", (todo_id,)
            )

        return cursor.rowcount > 0
