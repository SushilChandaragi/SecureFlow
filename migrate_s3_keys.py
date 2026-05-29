"""One-time migration: rename S3 keys that contain spaces or special characters.

Copies each unsafe object to a new RFC-3986-safe key (spaces -> underscores),
then deletes the old key. Safe for re-running — already-clean keys are skipped.
"""
import os
import re
import boto3
from dotenv import load_dotenv

load_dotenv()

s3 = boto3.client("s3")
bucket = os.environ["S3_BUCKET_NAME"]

resp = s3.list_objects_v2(Bucket=bucket)
contents = resp.get("Contents", [])

if not contents:
    print("Bucket is empty — nothing to migrate.")
else:
    for obj in contents:
        old_key = obj["Key"]
        new_key = re.sub(r"[^A-Za-z0-9._-]", "_", old_key)
        if old_key == new_key:
            print(f"  OK (already safe): {old_key}")
            continue
        print(f"  Migrating: \"{old_key}\"  ->  \"{new_key}\"")
        s3.copy_object(
            Bucket=bucket,
            CopySource={"Bucket": bucket, "Key": old_key},
            Key=new_key,
        )
        s3.delete_object(Bucket=bucket, Key=old_key)
        print(f"  Done.")

print("\nMigration complete. Re-run to verify all keys are now safe.")
