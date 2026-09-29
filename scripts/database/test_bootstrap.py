"""Behavior checks against PostgreSQL 17, without AWS credentials."""
import os
import unittest
from unittest.mock import Mock, patch

import psycopg

from bootstrap import bootstrap, connect
from runtime_secret import DATABASES, seed, validate


def fixture():
    return {"version": 1, "database": {
        name: {"username": "fiapx_admin" if name == "master" else name, "password": "local_test_password_" + name + "_" * 40}
        for name in ("master", *DATABASES)
    }, "jwt": {"private_key": "-----BEGIN PRIVATE KEY-----\ntest", "public_key": "-----BEGIN PUBLIC KEY-----\ntest"},
        "identity_service_key": "local_test_key_" + "x" * 40}


class SecretTests(unittest.TestCase):
    def test_user_defined_passwords_have_no_local_length_or_character_policy(self):
        for password in ("a", "ç @/'\"\\\u00a0", "x" * 256):
            with self.subTest(length=len(password)):
                value = fixture()
                for account in value["database"].values():
                    account["password"] = password
                value["identity_service_key"] = password
                self.assertIs(validate(value), value)

    def test_existing_secret_is_not_regenerated_or_overwritten(self):
        client = Mock()
        with patch("runtime_secret.load", return_value=fixture()), patch("runtime_secret.generate") as generate:
            self.assertIn("preserved", seed(client))
            generate.assert_not_called()
            client.create_secret.assert_not_called()
            client.put_secret_value.assert_not_called()


@unittest.skipUnless(os.environ.get("FIAPX_TEST_PORT"), "Use make verify-database for real PostgreSQL checks")
class DatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.settings = {"host": "127.0.0.1", "port": int(os.environ["FIAPX_TEST_PORT"]), "sslmode": "disable"}
        cls.value = fixture()
        for name, password in zip(DATABASES, ("a", "ç @/'\"\\\u00a0", "x" * 256)):
            cls.value["database"][name]["password"] = password
        cls.superuser = {"username": "postgres", "password": cls.value["database"]["master"]["password"]}
        bootstrap(cls.settings, cls.value)

    def test_rerun_preserves_data_passwords_and_isolation(self):
        name = DATABASES[0]
        with connect(self.settings, self.value["database"][name], name) as conn:
            conn.execute("CREATE TABLE sentinel (value text)")
            conn.execute("INSERT INTO sentinel VALUES ('preserved')")
        with connect(self.settings, self.superuser, "postgres") as conn:
            before = conn.execute("SELECT rolname, rolpassword FROM pg_authid WHERE rolname LIKE 'fiapx_%' ORDER BY rolname").fetchall()
        bootstrap(self.settings, self.value)
        with connect(self.settings, self.value["database"][name], name) as conn:
            self.assertEqual(conn.execute("SELECT value FROM sentinel").fetchone()[0], "preserved")
        with connect(self.settings, self.superuser, "postgres") as conn:
            self.assertEqual(before, conn.execute("SELECT rolname, rolpassword FROM pg_authid WHERE rolname LIKE 'fiapx_%' ORDER BY rolname").fetchall())

    def test_rejects_existing_privileged_role(self):
        with connect(self.settings, self.value["database"]["master"], "postgres") as conn:
            conn.execute("ALTER ROLE fiapx_video CREATEDB")
            try:
                with self.assertRaisesRegex(ValueError, "elevated"):
                    bootstrap(self.settings, self.value)
            finally:
                conn.execute("ALTER ROLE fiapx_video NOCREATEDB")

    def test_rejects_owner_conflict(self):
        with connect(self.settings, self.value["database"]["master"], "postgres") as conn:
            conn.execute("ALTER DATABASE fiapx_processing OWNER TO fiapx_admin")
            try:
                with self.assertRaisesRegex(ValueError, "unexpected owner"):
                    bootstrap(self.settings, self.value)
            finally:
                conn.execute("ALTER DATABASE fiapx_processing OWNER TO fiapx_processing")


if __name__ == "__main__":
    unittest.main()
