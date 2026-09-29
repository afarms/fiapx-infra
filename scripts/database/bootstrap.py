"""Idempotent database setup, executed on the private administration host."""
import secrets

import boto3
import psycopg
from psycopg import sql

from runtime_secret import DATABASES, load


def scram(conn, username, password):
    # libpq handles PostgreSQL password normalization, including Unicode.
    # Only the verifier is included in SQL, never the plaintext password.
    return conn.pgconn.encrypt_password(password.encode("utf-8"), username.encode("utf-8"), b"scram-sha-256").decode("ascii")


def connect(settings, account, database):
    return psycopg.connect(**settings, user=account["username"], password=account["password"],
                          dbname=database, autocommit=True, connect_timeout=15)


def bootstrap(settings, value):
    credentials = value["database"]
    master = credentials["master"]
    with connect(settings, master, "postgres") as conn:
        conn.execute("SELECT pg_advisory_lock(53005003)")
        for name in DATABASES:
            role = conn.execute("SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls FROM pg_roles WHERE rolname=%s", (name,)).fetchone()
            if role is None:
                conn.execute(sql.SQL("CREATE ROLE {} LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD {}").format(sql.Identifier(name), sql.Literal(scram(conn, name, credentials[name]["password"]))))
            elif any(role):
                raise ValueError("Application role has unexpected elevated privileges")
            if conn.execute("SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname=%s", (name,)).fetchone():
                raise ValueError("Application role has unexpected memberships")
            conn.execute(sql.SQL("GRANT {} TO {} WITH INHERIT TRUE, SET TRUE").format(sql.Identifier(name), sql.Identifier(master["username"])))
        for name in DATABASES:
            owner = conn.execute("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=%s", (name,)).fetchone()
            if owner is None:
                conn.execute(sql.SQL("CREATE DATABASE {} OWNER {} TEMPLATE template0 ENCODING 'UTF8'").format(sql.Identifier(name), sql.Identifier(name)))
            elif owner[0] != name:
                raise ValueError("Existing database has an unexpected owner")
            conn.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(sql.Identifier(name)))
            for other in DATABASES:
                if other != name:
                    conn.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM {}").format(sql.Identifier(name), sql.Identifier(other)))
            with connect(settings, master, name) as database:
                database.execute("REVOKE ALL ON SCHEMA public FROM PUBLIC")
                database.execute(sql.SQL("ALTER SCHEMA public OWNER TO {}").format(sql.Identifier(name)))
        validate(settings, value)
        conn.execute("SELECT pg_advisory_unlock(53005003)")


def validate(settings, value):
    for name in DATABASES:
        with connect(settings, value["database"][name], name) as conn:
            if settings.get("sslmode") == "verify-full" and not conn.execute("SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()").fetchone()[0]:
                raise ValueError("TLS required")
            # Roll back the probe, leaving application schemas untouched.
            with conn.transaction(force_rollback=True):
                probe = sql.Identifier("bootstrap_probe_" + secrets.token_hex(8))
                conn.execute(sql.SQL("CREATE TABLE public.{} (value integer)").format(probe))
                conn.execute(sql.SQL("INSERT INTO public.{} VALUES (1)").format(probe))
            for other in DATABASES:
                if other == name:
                    continue
                if conn.execute("SELECT has_database_privilege(current_user, %s, 'CONNECT')", (other,)).fetchone()[0]:
                    raise ValueError("Cross-database CONNECT privilege was unexpectedly granted")
                try:
                    with connect(settings, value["database"][name], other):
                        pass
                except psycopg.OperationalError as error:
                    # libpq startup failures have no structured SQLSTATE here.
                    # Do not mistake timeouts or authentication failures for isolation.
                    if f'permission denied for database "{other}"' in str(error):
                        continue
                    raise
                raise ValueError("Cross-database connection was unexpectedly permitted")


def main():
    try:
        session = boto3.Session(region_name="us-east-1")
        value = load(session.client("secretsmanager"))
        database = session.client("rds").describe_db_instances(DBInstanceIdentifier="fiapx-postgres")["DBInstances"][0]
        if database["PubliclyAccessible"] or not database["StorageEncrypted"]:
            raise ValueError("Unexpected RDS configuration")
        settings = {"host": database["Endpoint"]["Address"], "port": database["Endpoint"]["Port"],
                    "sslmode": "verify-full", "sslrootcert": "/opt/fiapx-database/rds-ca.pem"}
        bootstrap(settings, value)
        print("Database bootstrap verified: three roles/databases, TLS, DDL and cross-database isolation. Credentials preserved.")
    except Exception:
        print("Database bootstrap failed; check RDS, secret, network and ownership. No SQL or credentials displayed.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
