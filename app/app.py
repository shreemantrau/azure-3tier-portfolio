import os
import pyodbc
from flask import Flask, jsonify, request

app = Flask(__name__)

def get_db_connection():
    server = "sql-3tier-shreyas.database.windows.net"
    database = "db-3tier"
    username = "sqladmin"
    password = os.environ.get("SQL_PASSWORD")
    # used the password below to generate 500 error to make sure wokrbooks on the portal work
    # password ="wrong-password-on-purpose"
    connection_string = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={username};"
        f"PWD={password};"
    )
    return pyodbc.connect(connection_string)

# Health check - lets us confirm the app is alive without touching the DB
@app.route("/health")
def health():
    return jsonify({"status": "ok"})

# List all tasks
@app.route("/tasks", methods=["GET"])
def get_tasks():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id, title, created_at FROM tasks")
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{"id": r[0], "title": r[1], "created_at": str(r[2])} for r in rows])

# Create a new task
@app.route("/tasks", methods=["POST"])
def create_task():
    title = request.json.get("title")
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("INSERT INTO tasks (title) VALUES (?)", title)
    conn.commit()
    conn.close()
    return jsonify({"status": "created"}), 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)