"""AWS S3 integration for SecureFlow.

This module provides a minimal, UI-agnostic bridge between the vault and S3.
"""
from __future__ import annotations

import io
import logging
import os
import re
from typing import List, Optional

import boto3
from botocore.exceptions import ClientError, NoCredentialsError, EndpointConnectionError
from dotenv import load_dotenv


class CloudManagerError(Exception):
    """Raised when cloud operations fail in a user-visible way."""


logger = logging.getLogger(__name__)


class CloudManager:
    """Simple S3 interface for SecureFlow."""

    def __init__(self) -> None:
        load_dotenv()
        bucket = os.getenv("S3_BUCKET_NAME")
        if not bucket:
            logger.error("Missing S3_BUCKET_NAME in .env")
            raise CloudManagerError("S3_BUCKET_NAME is not set in .env.")

        region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
        session = boto3.session.Session(region_name=region)
        self._s3 = session.client("s3")
        self._bucket = bucket

    @property
    def bucket(self) -> str:
        return self._bucket

    def upload_vault_file(
        self,
        local_filepath: str,
        object_name: Optional[str] = None,
        delete_local: bool = False,
    ) -> None:
        """Upload a local .enc file to S3.

        The S3 object key is sanitised to RFC-3986-safe characters (spaces and
        special characters replaced with underscores) so that the Dart
        aws_signature_v4 signer can sign the download request correctly on
        mobile.  The local file is never renamed — only the S3 key changes.

        If delete_local is True, the local file is removed after upload.
        """
        if not os.path.isfile(local_filepath):
            raise CloudManagerError(f"Local file not found: {local_filepath}")

        raw_key = object_name or os.path.basename(local_filepath)
        # Replace any character outside A-Z a-z 0-9 . _ - with underscore.
        # This guarantees the S3 key is valid for SigV4 canonical path signing
        # on all clients (boto3, aws_signature_v4 Dart, etc.).
        key = re.sub(r"[^A-Za-z0-9._-]", "_", raw_key)
        if key != raw_key:
            logger.info("S3 key sanitised: '%s' -> '%s'", raw_key, key)
        try:
            self._s3.upload_file(local_filepath, self._bucket, key)
        except (ClientError, NoCredentialsError, EndpointConnectionError) as exc:
            logger.exception("S3 upload failed")
            raise CloudManagerError(f"Upload failed: {exc}") from exc

        if delete_local:
            try:
                os.remove(local_filepath)
            except OSError as exc:
                logger.exception("Local delete failed after upload")
                raise CloudManagerError(f"Upload succeeded, but delete failed: {exc}") from exc

    def get_vault_inventory(self) -> List[str]:
        """Return a list of object keys currently in the bucket."""
        keys: List[str] = []
        token: Optional[str] = None

        try:
            while True:
                kwargs = {"Bucket": self._bucket}
                if token:
                    kwargs["ContinuationToken"] = token

                response = self._s3.list_objects_v2(**kwargs)
                contents = response.get("Contents", [])
                keys.extend(obj["Key"] for obj in contents if "Key" in obj)

                if not response.get("IsTruncated"):
                    break
                token = response.get("NextContinuationToken")
        except (ClientError, NoCredentialsError, EndpointConnectionError) as exc:
            logger.exception("S3 list failed")
            raise CloudManagerError(f"Unable to list bucket: {exc}") from exc

        return sorted(keys)

    def download_to_buffer(self, object_name: str) -> io.BytesIO:
        """Download an object directly into a RAM buffer (no disk writes)."""
        buffer = io.BytesIO()
        try:
            self._s3.download_fileobj(self._bucket, object_name, buffer)
        except (ClientError, NoCredentialsError, EndpointConnectionError) as exc:
            logger.exception("S3 download failed")
            raise CloudManagerError(f"Download failed: {exc}") from exc

        buffer.seek(0)
        return buffer

    def delete_vault_file(self, object_name: str) -> None:
        """Delete an object from S3."""
        try:
            self._s3.delete_object(Bucket=self._bucket, Key=object_name)
        except (ClientError, NoCredentialsError, EndpointConnectionError) as exc:
            logger.exception("S3 delete failed")
            raise CloudManagerError(f"Delete failed: {exc}") from exc
