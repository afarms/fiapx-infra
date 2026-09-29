"""Run the exact Terraform document version; output only sanitized status."""
import json
import subprocess
import time

import boto3
from botocore.exceptions import ClientError


def main():
    try:
        metadata = json.loads(subprocess.run(["terraform", "-chdir=terraform", "output", "-json", "database_bootstrap"],
                                             check=True, capture_output=True).stdout)
        client = boto3.client("ssm", region_name="us-east-1")
        response = client.send_command(InstanceIds=[metadata["instance"]], DocumentName=metadata["document"],
                                       DocumentVersion=str(metadata["version"]), TimeoutSeconds=120,
                                       Comment="FIAP X database bootstrap and isolation validation")
        command_id = response["Command"]["CommandId"]
        print("Database bootstrap command submitted:", command_id, flush=True)
        deadline = time.monotonic() + 1200
        while time.monotonic() < deadline:
            time.sleep(10)
            try:
                result = client.get_command_invocation(CommandId=command_id, InstanceId=metadata["instance"])
            except ClientError as error:
                if error.response["Error"]["Code"] == "InvocationDoesNotExist":
                    continue
                raise
            status = result["Status"]
            if status in ("Pending", "InProgress", "Delayed", "Cancelling"):
                continue
            print("Database bootstrap status:", status)
            return 0 if status == "Success" else 1
        print("Database bootstrap observation timed out; inspect the command before retrying.")
    except Exception:
        print("Unable to run or observe database bootstrap; inspect IAM and SSM. No command output displayed.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
