#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import requests

from ensure_asc_app import BASE_URL, make_session


def env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def request(session: requests.Session, method: str, path: str, **kwargs) -> requests.Response:
    response = session.request(method, f"{BASE_URL}{path}", timeout=30, **kwargs)
    if response.status_code >= 400:
        print(f"{method} {path} failed: {response.status_code} {response.text[:2000]}", file=sys.stderr)
    response.raise_for_status()
    return response


def first_page(session: requests.Session, path: str, params: dict[str, str]) -> list[dict]:
    return request(session, "GET", path, params=params).json().get("data", [])


def find_build(session: requests.Session, app_id: str, build_number: str) -> dict | None:
    builds = first_page(
        session,
        "/builds",
        {
            "filter[app]": app_id,
            "filter[version]": build_number,
            "fields[builds]": "version,processingState,expired,usesNonExemptEncryption",
            "limit": "10",
        },
    )
    return builds[0] if builds else None


def wait_for_build(session: requests.Session, app_id: str, build_number: str, timeout_seconds: int) -> dict:
    deadline = time.time() + timeout_seconds
    last_state = "missing"
    while time.time() < deadline:
        build = find_build(session, app_id, build_number)
        if build:
            last_state = build["attributes"].get("processingState", "UNKNOWN")
            print(f"BUILD_ID={build['id']} PROCESSING_STATE={last_state}")
            if last_state in {"VALID", "FAILED", "INVALID"}:
                if last_state != "VALID":
                    raise SystemExit(f"Build processing ended as {last_state}")
                return build
        time.sleep(30)
    raise SystemExit(f"Timed out waiting for build {build_number}; last state: {last_state}")


def ensure_export_compliance(session: requests.Session, build: dict) -> dict:
    build_id = build["id"]
    if build.get("attributes", {}).get("usesNonExemptEncryption") is False:
        print("EXPORT_COMPLIANCE=false")
        return build
    updated = request(
        session,
        "PATCH",
        f"/builds/{build_id}",
        json={"data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}},
    ).json()["data"]
    print("EXPORT_COMPLIANCE_SET=false")
    return updated


def ensure_group(session: requests.Session, app_id: str, name: str, is_internal: bool) -> dict:
    groups = first_page(session, "/betaGroups", {"filter[app]": app_id, "limit": "100"})
    for group in groups:
        if group["attributes"].get("name") == name:
            print(f"BETA_GROUP_ID={group['id']}")
            return group
    group = request(
        session,
        "/betaGroups",
        json={
            "data": {
                "type": "betaGroups",
                "attributes": {"name": name, "isInternalGroup": is_internal, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    ).json()["data"]
    print(f"BETA_GROUP_ID={group['id']}")
    return group


def ensure_build_notes(session: requests.Session, build_id: str, whats_new: str) -> None:
    localizations = first_page(
        session,
        "/betaBuildLocalizations",
        {"filter[build]": build_id, "fields[betaBuildLocalizations]": "locale,whatsNew", "limit": "20"},
    )
    for localization in localizations:
        if localization["attributes"].get("locale") == "zh-Hans":
            request(
                session,
                "PATCH",
                f"/betaBuildLocalizations/{localization['id']}",
                json={
                    "data": {
                        "type": "betaBuildLocalizations",
                        "id": localization["id"],
                        "attributes": {"whatsNew": whats_new},
                    }
                },
            )
            return
    request(
        session,
        "/betaBuildLocalizations",
        json={
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": "zh-Hans", "whatsNew": whats_new},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        },
    )


def add_build_to_group(session: requests.Session, build_id: str, group_id: str) -> None:
    try:
        request(
            session,
            "POST",
            f"/builds/{build_id}/relationships/betaGroups",
            json={"data": [{"type": "betaGroups", "id": group_id}]},
        )
        print(f"BUILD_ADDED_TO_GROUP={group_id}")
    except requests.HTTPError as error:
        if error.response is not None and error.response.status_code in {409, 422}:
            print(f"BUILD_GROUP_LINK_SKIPPED={group_id}")
            return
        raise


def ensure_tester(session: requests.Session, email: str) -> dict | None:
    testers = first_page(session, "/betaTesters", {"filter[email]": email, "limit": "1"})
    if testers:
        return testers[0]
    local = email.split("@", 1)[0].replace(".", " ").replace("_", " ").strip()
    payload = {
        "data": {
            "type": "betaTesters",
            "attributes": {"email": email, "firstName": local[:30] or "Test", "lastName": "Tester"},
        }
    }
    try:
        return request(session, "POST", "/betaTesters", json=payload).json()["data"]
    except requests.HTTPError as error:
        if error.response is not None and error.response.status_code in {409, 422}:
            testers = first_page(session, "/betaTesters", {"filter[email]": email, "limit": "1"})
            return testers[0] if testers else None
        raise


def add_testers(session: requests.Session, group_id: str, emails: list[str]) -> tuple[list[dict], list[str]]:
    added: list[str] = []
    missing: list[str] = []
    failed: list[str] = []
    added_testers: list[dict] = []
    for email in emails:
        tester = ensure_tester(session, email)
        if not tester:
            missing.append(email)
            continue
        try:
            request(
                session,
                "POST",
                f"/betaGroups/{group_id}/relationships/betaTesters",
                json={"data": [{"type": "betaTesters", "id": tester["id"]}]},
            )
            added.append(email)
            added_testers.append(tester)
        except requests.HTTPError as error:
            if error.response is not None and error.response.status_code in {409, 422}:
                failed.append(email)
                continue
            raise
    print("TESTERS_REQUESTED=" + ",".join(added))
    print("TESTERS_MISSING=" + ",".join(missing))
    print("TESTERS_FAILED_ASSIGN=" + ",".join(failed))
    return added_testers, failed


def assign_testers_via_itms(group_id: str, emails: list[str]) -> None:
    fallback = Path("/Users/macstar/studyLog/scripts/assign_testflight_testers_via_itms.py")
    if not emails:
        return
    if not fallback.exists():
        print("ITMS_ASSIGN_SKIPPED=missing_script")
        return
    if not os.getenv("ASC_APP_PASSWORD"):
        print("ITMS_ASSIGN_SKIPPED=missing_ASC_APP_PASSWORD")
        return
    completed = subprocess.run(
        [sys.executable, str(fallback)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env={**os.environ, "BETA_GROUP_ID": group_id, "TESTER_EMAILS": ",".join(emails)},
    )
    print(completed.stdout, end="")


def main() -> None:
    session = make_session()
    app_id = env("ASC_APP_ID")
    build_number = env("APP_BUILD_NUMBER")
    group_name = env("TESTFLIGHT_GROUP_NAME", "PAICC Internal")
    is_internal = env("TESTFLIGHT_INTERNAL", "1") not in {"0", "false", "False", "no", "NO"}
    emails = [item.strip() for item in env("TESTER_EMAILS").split(",") if item.strip()]
    build = wait_for_build(session, app_id, build_number, int(env("BUILD_WAIT_SECONDS", "1800")))
    build = ensure_export_compliance(session, build)
    group = ensure_group(session, app_id, group_name, is_internal)
    ensure_build_notes(session, build["id"], env("WHAT_TO_TEST"))
    add_build_to_group(session, build["id"], group["id"])
    testers, failed = add_testers(session, group["id"], emails)
    assign_testers_via_itms(group["id"], failed)
    print("TESTFLIGHT_CONFIGURED=true")


if __name__ == "__main__":
    main()