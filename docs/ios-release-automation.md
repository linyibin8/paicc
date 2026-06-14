# PAI-CC iOS Release Automation

This project uses the Mac publisher at `macstar@100.64.0.6` for iOS releases.
Linux servers can host the backend, but they cannot archive, sign, or upload iOS
apps because those steps require Xcode and macOS signing tools.

## One-command release

On the Mac publisher:

```bash
cd /Users/macstar/projects/pai-cc
python3 scripts/ios_release_manager.py publish --sync-ssh ydz@100.64.0.13:/home/ydz/projects/pai-cc
```

The command syncs the current iOS source from the Ubuntu project, creates a
timestamped backup of the Mac release directory, builds the app, signs it,
uploads it to TestFlight, waits for processing, and attaches the build to the
configured TestFlight group.

## Useful commands

```bash
python3 scripts/ios_release_manager.py preflight
python3 scripts/ios_release_manager.py status
python3 scripts/ios_release_manager.py publish
```

Use `--version` or `--build-number` only when a manual override is required.
By default, the marketing version comes from `project.yml` and the build number
is the current timestamp.

## Secret handling

Secret values stay on the Mac publisher:

- `/Users/macstar/testflight-auto/ios-publish.env`
- `/Users/macstar/testflight-auto/ios-publish-paicc.env`
- App Store Connect `.p8` files
- signing certificate PEM/private key material

Do not commit those values or print them in logs. The release manager only
prints variable names, paths, build numbers, and public App Store Connect state.

## Entitlements Rule

Do not sign the app with every entitlement copied from the provisioning profile.
The profile can authorize more capabilities than the app actually uses. The
release manager writes a minimal distribution entitlements file and deliberately
omits unused capabilities such as `com.apple.developer.networking.networkextension`,
because App Store Connect rejects this app when `hotspot-provider` is present.

## Optional HTTP API

For a local-only API:

```bash
python3 scripts/ios_release_manager.py serve --host 127.0.0.1 --port 8765
```

For a network-accessible API, set a bearer token first:

```bash
export IOS_PUBLISH_TOKEN='<secret-token>'
python3 scripts/ios_release_manager.py serve --host 0.0.0.0 --port 8765
```

Then trigger a release:

```bash
curl -X POST http://127.0.0.1:8765/publish \
  -H "Authorization: Bearer $IOS_PUBLISH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sync_ssh":"ydz@100.64.0.13:/home/ydz/projects/pai-cc"}'
```
