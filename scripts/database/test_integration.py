"""Own and remove one temporary container, exposing PostgreSQL on loopback only."""
import os
import subprocess
import sys
import time
import uuid

name = "fiapx-bootstrap-test-" + uuid.uuid4().hex[:12]
started = False
try:
    subprocess.run(["docker", "run", "--detach", "--name", name,
                    "--publish", "127.0.0.1::5432", "--env", "POSTGRES_USER=postgres",
                    "--env", "POSTGRES_PASSWORD=local_test_password_master" + "_" * 40,
                    "postgres:17.11"], check=True, stdout=subprocess.DEVNULL)
    started = True
    for attempt in range(60):
        result = subprocess.run(["docker", "exec", name, "pg_isready", "-U", "postgres"], capture_output=True)
        if result.returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError("Temporary PostgreSQL did not become ready")
    port = subprocess.run(["docker", "port", name, "5432"], check=True, capture_output=True, text=True).stdout.strip().split(":")[-1]
    # RDS master is not a PostgreSQL superuser. Exercise CREATE ROLE/DB without it.
    subprocess.run(["docker", "exec", name, "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-c",
                    "CREATE ROLE fiapx_admin LOGIN CREATEDB CREATEROLE PASSWORD 'local_test_password_master" + "_" * 40 + "'"],
                   check=True, stdout=subprocess.DEVNULL)
    environment = dict(os.environ, FIAPX_TEST_PORT=port)
    result = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "scripts/database", "-p", "test_bootstrap.py", "-v"], env=environment)
    raise SystemExit(result.returncode)
finally:
    if started:
        subprocess.run(["docker", "rm", "--force", "--volumes", name], check=True, stdout=subprocess.DEVNULL)
