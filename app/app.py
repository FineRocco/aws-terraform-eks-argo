from flask import Flask
import psycopg2
import os

app = Flask(__name__)

@app.route("/")
def get_secret_from_rds():
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASS'),
            sslmode='require'
        )
        cursor = conn.cursor()
        
        cursor.execute("SELECT secret_value FROM my_secrets LIMIT 1;")
        secret = cursor.fetchone()[0]
        
        return f"<h1>Success!</h1><p>The secret retrieved from AWS RDS is: <strong>{secret}</strong></p>"
        
    except Exception as e:
        return f"<h1>Error connecting to RDS</h1><p>{str(e)}</p>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)