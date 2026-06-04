#!/usr/bin/env python3
"""Probe the current ClipDock server-mediated sync and P2P metadata flow.

This is not a true P2P/direct-device byte-transfer test. It verifies the
implemented server pairing and P2P coordination metadata model:

- device A creates a sync space and receives a 5-character pairing code
- device B joins that sync space with the code
- device B can pull device A's event and asset through the server
- device A can report a P2P endpoint and asset provider record
- device B can discover device A's P2P metadata inside the same sync space
- an unrelated sync space cannot see those events or assets

By default the script starts a temporary local server instance. Pass
--base-url to probe an already running server.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
LISTEN_RE = re.compile(r"ClipDock sync server listening on (http://[^\s]+)")


@dataclass
class HttpResult:
    status: int
    headers: dict[str, str]
    body: bytes

    def json(self) -> dict[str, Any]:
        return json.loads(self.body.decode("utf-8"))


class ProbeFailure(RuntimeError):
    pass


def request(
    method: str,
    url: str,
    *,
    token: str | None = None,
    json_body: dict[str, Any] | None = None,
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
) -> HttpResult:
    headers = dict(headers or {})
    data = body
    if json_body is not None:
        data = json.dumps(json_body, separators=(",", ":")).encode("utf-8")
        headers.setdefault("content-type", "application/json")
    if token:
        headers["authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return HttpResult(
                status=response.status,
                headers={key.lower(): value for key, value in response.headers.items()},
                body=response.read(),
            )
    except urllib.error.HTTPError as error:
        return HttpResult(
            status=error.code,
            headers={key.lower(): value for key, value in error.headers.items()},
            body=error.read(),
        )


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise ProbeFailure(message)


def expect_json_status(result: HttpResult, status: int, label: str) -> dict[str, Any]:
    expect(result.status == status, f"{label}: expected {status}, got {result.status}: {result.body!r}")
    content_type = result.headers.get("content-type", "")
    expect("application/json" in content_type, f"{label}: expected json content-type, got {content_type!r}")
    payload = result.json()
    expect(payload.get("protocol_version") == 2, f"{label}: missing protocol_version=2")
    return payload


def start_server() -> tuple[str, tempfile.TemporaryDirectory[str], subprocess.Popen[str]]:
    temp_dir = tempfile.TemporaryDirectory(prefix="clipdock-sync-probe.")
    db_path = Path(temp_dir.name) / "clipdock-sync.sqlite"
    asset_dir = Path(temp_dir.name) / "assets"
    cmd = [
        "cargo",
        "run",
        "--quiet",
        "--",
        "--bind",
        "127.0.0.1:0",
        "--database",
        str(db_path),
        "--assets",
        str(asset_dir),
        "--max-asset-bytes",
        "2097152",
    ]
    process = subprocess.Popen(
        cmd,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    deadline = time.monotonic() + 30
    output_lines: list[str] = []
    assert process.stdout is not None
    while time.monotonic() < deadline:
        line = process.stdout.readline()
        if line:
            output_lines.append(line.rstrip())
            match = LISTEN_RE.search(line)
            if match:
                return match.group(1), temp_dir, process
        elif process.poll() is not None:
            break
    process.terminate()
    temp_dir.cleanup()
    raise ProbeFailure("server did not start:\n" + "\n".join(output_lines))


def stop_server(process: subprocess.Popen[str] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def sha256_digest(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


def p2p_asset_id(data: bytes) -> str:
    return blake3_probe_digest(data)


def blake3_probe_digest(data: bytes) -> str:
    fixtures = {
        b"ClipDock sync probe asset": "904dbaddc51270e60ad53c600b922a047db84d6774d3832cfba065d674f5af98",
        b"ClipDock sync probe item": "6c75ac7a294f19fe4a1c6f46451862aa76d44af1880cd91953f5237b5435d5b6",
        b"ClipDock P2P probe large payload": "d15501fd5d941939eff81a89ca21736d639ec71e3f32b7f2f7cbd7c30ed21cb5",
    }
    try:
        return f"blake3:{fixtures[data]}"
    except KeyError as error:
        raise ProbeFailure(f"missing fixed BLAKE3 fixture for {data!r}") from error


def run_probe(base_url: str) -> dict[str, Any]:
    base_url = base_url.rstrip("/")

    health = expect_json_status(request("GET", f"{base_url}/health"), 200, "health")
    expect(health["data"]["status"] == "ok", "health: unexpected status body")

    retired_v1 = expect_json_status(request("GET", f"{base_url}/v1/info"), 426, "v1 retired")
    expect(retired_v1["error"]["code"] == "protocol_v1_retired", "v1 retired: wrong error code")

    create_a = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/sync/create",
            json_body={"device_name": "Probe Mac A"},
        ),
        200,
        "create A",
    )["data"]
    sync_id = create_a["sync_id"]
    token_a = create_a["token"]
    pairing_code = create_a["pairing_code"]
    expect(sync_id.startswith("sync_"), "create A: sync_id should start with sync_")
    expect(token_a.startswith("cds_"), "create A: token should start with cds_")
    expect(len(pairing_code) == 5 and pairing_code.isalnum(), "create A: invalid pairing code")

    join_b = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/sync/join",
            json_body={"device_name": "Probe Android B", "pairing_code": pairing_code},
        ),
        200,
        "join B",
    )["data"]
    token_b = join_b["token"]
    expect(join_b["sync_id"] == sync_id, "join B: sync_id mismatch")
    expect(token_b.startswith("cds_"), "join B: token should start with cds_")

    reused = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/sync/join",
            json_body={"device_name": "Probe Reuse", "pairing_code": pairing_code},
        ),
        403,
        "reuse pairing code",
    )
    expect(reused["error"]["code"] == "invalid_pairing_code", "reuse: wrong error code")

    create_other = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/sync/create",
            json_body={"device_name": "Probe Other Space"},
        ),
        200,
        "create other",
    )["data"]
    token_other = create_other["token"]

    info_b = expect_json_status(
        request("GET", f"{base_url}/v2/info", token=token_b),
        200,
        "info B",
    )["data"]
    expect(info_b["content_hash_algorithms"] == ["blake3"], "info B: wrong content hash algorithms")
    expect(info_b["asset_digest_algorithms"] == ["blake3"], "info B: wrong asset digest algorithms")
    expect(info_b["p2p"]["enabled"] is True, "info B: P2P should be enabled")
    expect(info_b["p2p"]["transport"] == "iroh-blobs", "info B: wrong P2P transport")

    report_endpoint = expect_json_status(
        request(
            "PUT",
            f"{base_url}/v2/p2p/endpoint",
            token=token_a,
            json_body={
                "endpoint_id": "probe-iroh-node-a",
                "relay_url": "https://relay.invalid.example",
                "direct_addresses": ["/ip4/127.0.0.1/udp/4433/quic-v1"],
                "capabilities": {"transport": "iroh-blobs", "blob_transfer": True},
                "quality": {
                    "path_type": "direct",
                    "rtt_ms": 12,
                    "throughput_bytes_per_sec": 12000000,
                },
            },
        ),
        200,
        "report A P2P endpoint",
    )["data"]
    expect(report_endpoint["device_id"] == create_a["device_id"], "P2P endpoint: device mismatch")

    p2p_devices_b = expect_json_status(
        request("GET", f"{base_url}/v2/p2p/devices", token=token_b),
        200,
        "list B P2P devices",
    )["data"]["devices"]
    expect(len(p2p_devices_b) == 1, "list B P2P devices: expected one endpoint")
    expect(p2p_devices_b[0]["device_id"] == create_a["device_id"], "list B P2P devices: wrong device")
    expect(
        p2p_devices_b[0]["endpoint"]["endpoint_id"] == "probe-iroh-node-a",
        "list B P2P devices: wrong endpoint",
    )

    p2p_devices_other = expect_json_status(
        request("GET", f"{base_url}/v2/p2p/devices", token=token_other),
        200,
        "list other P2P devices",
    )["data"]["devices"]
    expect(len(p2p_devices_other) == 0, "list other P2P devices: expected isolation")

    item_text = "ClipDock sync probe item"
    sha256_content_hash = sha256_digest(item_text.encode("utf-8"))
    sha256_event = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/events",
            token=token_a,
            json_body={
                "events": [
                    {
                        "client_event_id": "probe-event-sha256-negative",
                        "type": "item_upsert",
                        "content_hash": sha256_content_hash,
                        "item_type": "text",
                        "payload": {"text": item_text},
                        "copy_count_delta": 1,
                    }
                ]
            },
        ),
        400,
        "reject SHA-256 content hash",
    )
    expect(sha256_event["error"]["code"] == "invalid_content_hash", "SHA-256 content hash: wrong error")

    content_hash = blake3_probe_digest(item_text.encode("utf-8"))
    push_event = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/events",
            token=token_a,
            json_body={
                "events": [
                    {
                        "client_event_id": "probe-event-1",
                        "type": "item_upsert",
                        "content_hash": content_hash,
                        "item_type": "text",
                        "payload": {"text": item_text},
                        "copy_count_delta": 1,
                    }
                ]
            },
        ),
        200,
        "push A event",
    )["data"]
    expect(push_event["events"][0]["duplicate"] is False, "push A event: expected first push")

    pull_b = expect_json_status(
        request("GET", f"{base_url}/v2/events?after_seq=0&limit=10", token=token_b),
        200,
        "pull B events",
    )["data"]
    expect(len(pull_b["events"]) == 1, "pull B events: expected one event")
    expect(pull_b["events"][0]["content_hash"] == content_hash, "pull B events: hash mismatch")

    pull_other = expect_json_status(
        request("GET", f"{base_url}/v2/events?after_seq=0&limit=10", token=token_other),
        200,
        "pull other events",
    )["data"]
    expect(len(pull_other["events"]) == 0, "pull other events: expected isolation")

    asset_bytes = b"ClipDock sync probe asset"
    sha256_asset_digest = sha256_digest(asset_bytes)
    sha256_asset = expect_json_status(
        request(
            "PUT",
            f"{base_url}/v2/assets/{sha256_asset_digest}",
            token=token_a,
            body=asset_bytes,
            headers={
                "content-type": "image/png",
                "x-clipdock-asset-kind": "thumbnail",
            },
        ),
        400,
        "reject SHA-256 asset digest",
    )
    expect(sha256_asset["error"]["code"] == "invalid_digest", "SHA-256 asset digest: wrong error")

    asset_digest = blake3_probe_digest(asset_bytes)
    upload = expect_json_status(
        request(
            "PUT",
            f"{base_url}/v2/assets/{asset_digest}",
            token=token_a,
            body=asset_bytes,
            headers={
                "content-type": "image/png",
                "x-clipdock-asset-kind": "thumbnail",
            },
        ),
        200,
        "upload asset",
    )["data"]
    expect(upload["already_exists"] is False, "upload asset: expected first upload")

    download_b = request("GET", f"{base_url}/v2/assets/{asset_digest}", token=token_b)
    expect(download_b.status == 200, f"download B asset: expected 200, got {download_b.status}")
    expect(download_b.body == asset_bytes, "download B asset: bytes mismatch")

    download_other = expect_json_status(
        request("GET", f"{base_url}/v2/assets/{asset_digest}", token=token_other),
        400,
        "download other asset",
    )
    expect(download_other["error"]["code"] == "asset_not_found", "download other asset: isolation failed")

    large_payload_asset_id = p2p_asset_id(b"ClipDock P2P probe large payload")
    register_provider = expect_json_status(
        request(
            "PUT",
            f"{base_url}/v2/p2p/assets/{large_payload_asset_id}/providers/me",
            token=token_a,
            json_body={
                "kind": "file_payload",
                "byte_count": 7340032,
                "mime_type": "application/octet-stream",
                "quality": {
                    "last_probe_path": "direct",
                    "throughput_bytes_per_sec": 12000000,
                },
            },
        ),
        200,
        "register A P2P provider",
    )["data"]
    expect(register_provider["asset_id"] == large_payload_asset_id, "P2P provider: asset mismatch")

    providers_b = expect_json_status(
        request(
            "GET",
            f"{base_url}/v2/p2p/assets/{large_payload_asset_id}/providers",
            token=token_b,
        ),
        200,
        "list B P2P providers",
    )["data"]["providers"]
    expect(len(providers_b) == 1, "list B P2P providers: expected one provider")
    expect(providers_b[0]["device_id"] == create_a["device_id"], "list B P2P providers: wrong device")
    expect(providers_b[0]["availability"] == "online", "list B P2P providers: provider should be online")
    expect(
        providers_b[0]["endpoint"]["endpoint_id"] == "probe-iroh-node-a",
        "list B P2P providers: endpoint missing",
    )

    providers_other = expect_json_status(
        request(
            "GET",
            f"{base_url}/v2/p2p/assets/{large_payload_asset_id}/providers",
            token=token_other,
        ),
        200,
        "list other P2P providers",
    )["data"]["providers"]
    expect(len(providers_other) == 0, "list other P2P providers: expected isolation")

    invite = expect_json_status(
        request("POST", f"{base_url}/v2/sync/invites", token=token_b),
        200,
        "create invite from B",
    )["data"]
    fresh_code = invite["pairing_code"]
    expect(invite["sync_id"] == sync_id, "fresh invite: sync_id mismatch")
    expect(len(fresh_code) == 5 and fresh_code.isalnum(), "fresh invite: invalid pairing code")

    join_c = expect_json_status(
        request(
            "POST",
            f"{base_url}/v2/sync/join",
            json_body={"device_name": "Probe Device C", "pairing_code": fresh_code},
        ),
        200,
        "join C",
    )["data"]
    expect(join_c["sync_id"] == sync_id, "join C: sync_id mismatch")

    return {
        "base_url": base_url,
        "sync_id": sync_id,
        "pairing_code_length": len(pairing_code),
        "device_b_received_events": len(pull_b["events"]),
        "other_space_received_events": len(pull_other["events"]),
        "device_b_asset_bytes": len(download_b.body),
        "other_space_asset_error": download_other["error"]["code"],
        "p2p_devices_visible_to_b": len(p2p_devices_b),
        "p2p_devices_visible_to_other": len(p2p_devices_other),
        "p2p_providers_visible_to_b": len(providers_b),
        "p2p_providers_visible_to_other": len(providers_other),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", help="Probe an already running server, for example http://127.0.0.1:8787")
    parser.add_argument("--keep-temp", action="store_true", help="Keep temporary server data when the script starts the server")
    args = parser.parse_args()

    process: subprocess.Popen[str] | None = None
    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    try:
        base_url = args.base_url
        if not base_url:
            base_url, temp_dir, process = start_server()
            print(f"started temporary server: {base_url}")
        summary = run_probe(base_url)
        print("PASS: server-mediated pairing sync and P2P metadata flow works")
        print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    finally:
        stop_server(process)
        if temp_dir is not None:
            temp_path = temp_dir.name
            if args.keep_temp:
                print(f"kept temporary data: {temp_path}")
                temp_dir._finalizer.detach()  # type: ignore[attr-defined]
            else:
                temp_dir.cleanup()
                if os.path.exists(temp_path):
                    shutil.rmtree(temp_path, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
