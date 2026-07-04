def get_user(conn, name):
    return conn.execute("SELECT * FROM users WHERE name = '%s'" % name).fetchall()
