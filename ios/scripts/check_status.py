#!/usr/bin/env python3
from __future__ import annotations

import os

from ensure_asc_app import api_get, make_session

APP_ID = os.getenv("ASC_APP_ID", "")
BUILD_NUMBER = os.getenv("APP_BUILD_NUMBER", "")
GROUP_NAME = os.getenv("TESTFLIGHT_GROUP_NAME", "PAICC Internal")


def main() -> None:
    session = make_session()
    if not APP_ID:
        apps = api_get(session, "/apps?filter[bundleId]=com.evowit.paicc")["data"]
        if not apps:
            raise SystemExit("APP_NOT_FOUND")
        app_id = apps[0]["id"]
    else:
        app_id = APP_ID
    print(f"ASC_APP_ID={app_id}")

    params = f"filter[app]={app_id}&fields[builds]=version,processingState,usesNonExemptEncryption&limit=10"
    if BUILD_NUMBER:
        params += f"&filter[version]={BUILD_NUMBER}"
    builds = api_get(session, f"/builds?{params}")["data"]
    for build in builds:
        attrs = build["attributes"]
        print(
            f"BUILD_ID={build['id']} BUILD_NUMBER={attrs.get('version')} "
            f"BUILD_STATE={attrs.get('processingState')} EXPORT_COMPLIANCE={attrs.get('usesNonExemptEncryption')}"
        )

    groups = api_get(session, f"/apps/{app_id}/betaGroups?fields[betaGroups]=name,isInternalGroup&limit=100")["data"]
    for group in groups:
        if group["attributes"].get("name") == GROUP_NAME:
            print(f"BETA_GROUP_ID={group['id']} GROUP_NAME={GROUP_NAME}")


if __name__ == "__main__":
    main()