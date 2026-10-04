import snowflake.connector
import os, sys, glob, warnings, json
warnings.filterwarnings('ignore')

# Check for cached tokens
cache_dir = os.path.expanduser('~/.snowflake')
print(f"Checking {cache_dir} for cached credentials...")
for f in glob.glob(os.path.join(cache_dir, '*')):
    fname = os.path.basename(f)
    fsize = os.path.getsize(f) if os.path.isfile(f) else 'dir'
    print(f"  {fname}: {fsize}")

# Try connecting with the connection.toml config using token_file_path if available
# Or try externalbrowser with no_browser mode
try:
    conn = snowflake.connector.connect(
        connection_name='CONN',
        client_store_temporary_credential=True,
    )
    cur = conn.cursor()
    cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_DATABASE()")
    print("Connected:", cur.fetchone())
    
    local_path = r'c:\Users\heman\OneDrive\Desktop\CoCoHackathon\supply-chain\validation\scenario_ground_truth\scenario_ground_truth.csv'
    put_sql = f"PUT 'file://{local_path}' @SUPPLY_CHAIN_DW.VALIDATION.GROUND_TRUTH_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
    print("Executing PUT...")
    cur.execute(put_sql)
    for row in cur:
        print("PUT:", row)
    cur.close()
    conn.close()
    print("Success")
except Exception as e:
    print(f"Error: {e}")
    
    # Try with externalbrowser
    print("\nTrying externalbrowser...")
    try:
        conn = snowflake.connector.connect(
            account='BYMJIUE-FC85049',
            user='MANCHIRAJUHEMANTH',
            authenticator='externalbrowser',
            database='SUPPLY_CHAIN_DW',
            schema='VALIDATION',
            client_store_temporary_credential=True,
        )
        cur = conn.cursor()
        cur.execute("SELECT CURRENT_USER()")
        print("Connected:", cur.fetchone())
        
        local_path = r'c:\Users\heman\OneDrive\Desktop\CoCoHackathon\supply-chain\validation\scenario_ground_truth\scenario_ground_truth.csv'
        cur.execute(f"PUT 'file://{local_path}' @SUPPLY_CHAIN_DW.VALIDATION.GROUND_TRUTH_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
        for row in cur:
            print("PUT:", row)
        cur.close()
        conn.close()
        print("Success")
    except Exception as e2:
        print(f"Error2: {e2}")
