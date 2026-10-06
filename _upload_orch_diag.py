import snowflake.connector
import os
import shutil
import tempfile

conn = snowflake.connector.connect(connection_name="HACK")
cur = conn.cursor()
cur.execute("USE ROLE ACCOUNTADMIN")
cur.execute("USE DATABASE SUPPLY_CHAIN_DW")
cur.execute("USE SCHEMA GOLD")

src = r"c:\Users\heman\OneDrive\Desktop\CoCoHackathon\streamlit_app\orch_diag.py"
tmp_dir = os.path.join(tempfile.gettempdir(), "sis_orchdiag")
os.makedirs(tmp_dir, exist_ok=True)
shutil.copy2(src, os.path.join(tmp_dir, "orch_diag.py"))

path = os.path.join(tmp_dir, "orch_diag.py").replace("\\", "/")
cur.execute("CREATE STAGE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.ORCH_DIAG_STAGE")
cur.execute(f"PUT file://{path} @SUPPLY_CHAIN_DW.GOLD.ORCH_DIAG_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
print(cur.fetchone())
cur.close()
conn.close()
shutil.rmtree(tmp_dir, ignore_errors=True)
print("Done")
