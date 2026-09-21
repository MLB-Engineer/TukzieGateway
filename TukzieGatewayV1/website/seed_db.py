import sqlite3
from passlib.context import CryptContext
import os

# We tell passlib to handle the 72-char limit automatically
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__truncate_error=True)
DB_FILE = "users.db"

def create_fresh_db():
    if os.path.exists(DB_FILE):
        try:
            os.remove(DB_FILE)
            print("Removed old database.")
        except PermissionError:
            print("Error: users.db is currently in use. Close your backend/terminal and try again.")
            return

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE users (
            email TEXT PRIMARY KEY,
            password TEXT,
            role TEXT
        )
    """)

    # Explicitly defining the passwords
    # .encode('utf-8')[:72] ensures we never hit the Bcrypt limit
    accounts = [
        ("operator", "operator2026", "operator"),
        ("developer", "developer2026", "developer"),
        ("guest", "guest", "guest")
    ]

    for email, plain_pw, role in accounts:
        # We hash the password here
        hashed_pw = pwd_context.hash(plain_pw)
        cursor.execute("INSERT INTO users VALUES (?, ?, ?)", (email, hashed_pw, role))
    
    conn.commit()
    conn.close()
    print(f"Successfully created {DB_FILE}")

if __name__ == "__main__":
    create_fresh_db()