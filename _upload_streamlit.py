import snowflake.connector
import os
import shutil
import tempfile

conn = snowflake.connector.connect(connection_name="HACK")
cur = conn.cursor()
cur.execute("USE ROLE ACCOUNTADMIN")
cur.execute("USE DATABASE SUPPLY_CHAIN_DW")
cur.execute("USE SCHEMA GOLD")

files = ["app.py", "agent_client.py", "chart_queries.py", "risk_cases.py", "environment.yml"]
src_dir = r"c:\Users\heman\OneDrive\Desktop\CoCoHackathon\streamlit_app"

tmp_dir = os.path.join(tempfile.gettempdir(), "sis_upload")
os.makedirs(tmp_dir, exist_ok=True)

for f in files:
    shutil.copy2(os.path.join(src_dir, f), os.path.join(tmp_dir, f))

for f in files:
    path = os.path.join(tmp_dir, f).replace("\\", "/")
    sql = f"PUT file://{path} @SUPPLY_CHAIN_DW.GOLD.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
    print(f"Executing: {sql}")
    cur.execute(sql)
    row = cur.fetchone()
    print(f"{f}: {row}")

cur.close()
conn.close()
shutil.rmtree(tmp_dir, ignore_errors=True)
print("Done")
