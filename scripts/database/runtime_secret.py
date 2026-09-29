"""Create the aggregate secret once; never rotate it on a rerun."""
import argparse
import json
import secrets
import subprocess

import boto3
from botocore.exceptions import ClientError

SECRET_NAME = "fiapx/runtime"
DATABASES = ("fiapx_identity", "fiapx_video", "fiapx_processing")
TAGS = {"Project": "fiapx", "ManagedBy": "terraform"}


def validate(value):
    if value.get("version") != 1:
        raise ValueError("Unsupported runtime secret schema")
    database = value["database"]
    for name in ("master", *DATABASES):
        account = database[name]
        expected = "fiapx_admin" if name == "master" else name
        if account["username"] != expected or not isinstance(account["password"], str) or not account["password"]:
            raise ValueError("Invalid database credentials in runtime secret")
    if not isinstance(value["identity_service_key"], str) or not value["identity_service_key"]:
        raise ValueError("Invalid service key")
    if not value["jwt"]["private_key"].startswith("-----BEGIN PRIVATE KEY-----") or not value["jwt"]["public_key"].startswith("-----BEGIN PUBLIC KEY-----"):
        raise ValueError("Invalid JWT key format")
    return value


def load(client):
    metadata = client.describe_secret(SecretId=SECRET_NAME)
    if metadata.get("DeletedDate") or dict((t["Key"], t["Value"]) for t in metadata.get("Tags", [])) != TAGS:
        raise ValueError("Runtime secret ownership must be verified before use")
    return validate(json.loads(client.get_secret_value(SecretId=SECRET_NAME)["SecretString"]))


def generate():
    private = subprocess.run(
        ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"],
        check=True, capture_output=True,
    ).stdout
    public = subprocess.run(["openssl", "pkey", "-pubout"], input=private, check=True, capture_output=True).stdout
    return {
        "version": 1,
        "database": {name: {"username": "fiapx_admin" if name == "master" else name, "password": secrets.token_urlsafe(32)} for name in ("master", *DATABASES)},
        "jwt": {"private_key": private.decode(), "public_key": public.decode()},
        "identity_service_key": secrets.token_urlsafe(32),
    }


def seed(client):
    try:
        load(client)
        return "Runtime secret already exists; credentials preserved."
    except ClientError as error:
        if error.response["Error"]["Code"] != "ResourceNotFoundException":
            raise
    value = validate(generate())
    try:
        client.create_secret(Name=SECRET_NAME, Description="FIAP X database and application credentials",
                             SecretString=json.dumps(value), Tags=[{"Key": k, "Value": v} for k, v in TAGS.items()])
    except ClientError as error:
        if error.response["Error"]["Code"] != "ResourceExistsException":
            raise
        load(client)
        return "Runtime secret created concurrently; credentials preserved."
    return "Runtime secret created; values were not written to files or output."


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile")
    args = parser.parse_args()
    try:
        client = boto3.Session(profile_name=args.profile, region_name="us-east-1").client("secretsmanager")
        print(seed(client))
    except Exception:
        # SDK, SQL and subprocess exception strings can contain credentials.
        print("Runtime secret bootstrap failed; check credentials, ownership and schema. No values displayed.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
