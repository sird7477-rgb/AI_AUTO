def get_user(conn, name):
    return conn.execute("SELECT * FROM users WHERE name = ?", (name,)).fetchall()
