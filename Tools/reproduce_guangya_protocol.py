#!/usr/bin/env python3
"""Independently reproduce the evidenced Guangya protocol without Android/JAR.

The default command runs offline fixture assertions. ``create-device`` performs only
OAuth device-code creation; it does not poll, persist credentials, or expose tokens.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

CLIENT_ID = "aMe-8VSlkrbQXpUR"
ACCOUNT_BASE = "https://account.guangyapan.com"
WEB_ORIGIN = "https://www.guangyapan.com"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)
FIXTURE_PATH = Path(__file__).with_name("fixtures") / "guangya_protocol.json"


def headers(authorization: str | None = None) -> dict[str, str]:
    result = {
        "User-Agent": USER_AGENT,
        "Referer": f"{WEB_ORIGIN}/",
        "Origin": WEB_ORIGIN,
        "Content-Type": "application/json",
    }
    if authorization:
        result["Authorization"] = authorization
    return result


def device_code_body() -> dict[str, str]:
    return {"scope": "user", "client_id": CLIENT_ID}


def poll_body(device_code: str) -> dict[str, str]:
    return {
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        "device_code": device_code,
        "client_id": CLIENT_ID,
    }


def refresh_body(refresh_token: str) -> dict[str, str]:
    return {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
    }


def payload(response: dict[str, Any]) -> dict[str, Any]:
    data = response.get("data")
    return data if isinstance(data, dict) else response


def first_string(*values: Any) -> str:
    return next((value.strip() for value in values if isinstance(value, str) and value.strip()), "")


def device_code_result(response: dict[str, Any]) -> tuple[str, str]:
    data = payload(response)
    return (
        first_string(data.get("device_code"), response.get("device_code")),
        first_string(
            data.get("verification_uri_complete"),
            response.get("verification_uri_complete"),
            data.get("verification_uri"),
            response.get("verification_uri"),
        ),
    )


def poll_succeeded(response: dict[str, Any]) -> bool:
    if first_string(response.get("error")):
        return False
    data = payload(response)
    return bool(first_string(data.get("access_token"), response.get("access_token")))


def deep_merge(base: dict[str, Any], update: dict[str, Any]) -> dict[str, Any]:
    """Merge dictionaries recursively while retaining unknown response fields."""
    result = copy.deepcopy(base)
    for key, value in update.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def merge_credential(stored: dict[str, Any], response: dict[str, Any]) -> dict[str, Any]:
    """Preserve raw JSON and project Android-compatible aliases into canonical keys."""
    merged = deep_merge(stored, response)
    old_data = stored.get("data") if isinstance(stored.get("data"), dict) else {}
    new_data = payload(response)
    for canonical, aliases in {
        "access_token": ("access_token", "accessToken"),
        "refresh_token": ("refresh_token", "refreshToken"),
        "token_type": ("token_type", "tokenType"),
        "sub": ("sub",),
        "phone": ("phone_number", "phone"),
        "kaiser_folder": ("kaiser_folder",),
    }.items():
        candidates = [new_data.get(alias) for alias in aliases]
        candidates += [response.get(alias) for alias in aliases]
        candidates += [old_data.get(alias) for alias in aliases]
        candidates += [stored.get(alias) for alias in aliases]
        value = first_string(*candidates)
        if value:
            merged[canonical] = value
    merged.setdefault("token_type", "Bearer")
    return merged


def merge_profile(stored: dict[str, Any], response: dict[str, Any]) -> dict[str, Any]:
    merged = deep_merge(stored, response)
    data = payload(response)
    aliases = {
        "sub": ("sub",),
        "name": ("name", "nickname"),
        "picture": ("picture", "avatar"),
        "phone": ("phone_number", "phone"),
    }
    for canonical, keys in aliases.items():
        value = first_string(*(data.get(key) for key in keys), *(response.get(key) for key in keys), stored.get(canonical))
        if value:
            merged[canonical] = value
    return merged


def download_url(response: dict[str, Any]) -> str:
    data = payload(response)
    keys = ("signedURL", "signedUrl", "downloadUrl", "downloadURL", "url")
    return first_string(*(data.get(key) for key in keys), *(response.get(key) for key in keys))


def post_json(url: str, body: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(body, separators=(",", ":")).encode(),
        headers=headers(),
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:500]
        raise RuntimeError(f"HTTP {error.code}: {detail}") from error


def self_test(path: Path) -> None:
    fixtures = json.loads(path.read_text(encoding="utf-8"))
    code, uri = device_code_result(fixtures["device_code"])
    assert code == "fixture-device-code" and uri == "https://fixture.invalid/authorize?code=ABCD"
    assert not poll_succeeded(fixtures["authorization_pending"])
    assert poll_succeeded(fixtures["poll_success"])

    merged = merge_credential(fixtures["stored"], fixtures["poll_success"])
    assert merged["access_token"] == "fixture-access-new"
    assert merged["refresh_token"] == "fixture-refresh-old"
    assert merged["unknown_root"]["keep"] is True
    assert merged["data"]["unknown_token_field"] == {"nested": 1}

    profiled = merge_profile(merged, fixtures["profile"])
    assert profiled["name"] == "Fixture User"
    assert profiled["picture"] == "https://fixture.invalid/avatar.png"
    assert profiled["profile_unknown"]["keep"] == "yes"
    assert download_url(fixtures["download"]) == "https://fixture.invalid/video.m3u8"
    assert poll_body("device") == {
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        "device_code": "device",
        "client_id": CLIENT_ID,
    }
    assert refresh_body("refresh") == {
        "grant_type": "refresh_token",
        "refresh_token": "refresh",
        "client_id": CLIENT_ID,
    }
    print("offline fixture reproduction: PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command")
    test_parser = subparsers.add_parser("self-test", help="run offline protocol fixtures")
    test_parser.add_argument("--fixtures", type=Path, default=FIXTURE_PATH)
    subparsers.add_parser("create-device", help="create one real device authorization request")
    args = parser.parse_args()

    if args.command in (None, "self-test"):
        self_test(getattr(args, "fixtures", FIXTURE_PATH))
        return
    response = post_json(f"{ACCOUNT_BASE}/v1/auth/device/code", device_code_body())
    code, uri = device_code_result(response)
    if not code or not uri:
        raise RuntimeError("device-code response lacks required fields")
    # Device code may be credential-like; print only the user-facing authorization URI.
    print(uri)


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, ValueError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
