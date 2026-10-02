# Scripts

| Path | Purpose |
| --- | --- |
| `install.sh` | Builds Ice (Release, ad hoc signed, hardened runtime off), checks the signature and installs it to `~/Applications`. `DEST=/Applications` installs it for all users. |
| `check-panels.swift` | Counts Ice's live windows by kind, to catch leaked overlay panels. Run with `swift check-panels.swift`. |
| `macos27/` | Checks for the macOS 27 code: each `verify-*.sh` drives an installed Ice and states its requirements at the top. The Swift files are the probes those scripts call. |

The release build, which `.github/workflows/release.yml` runs for every `v*` tag, uses the same flags as `install.sh`.

## Sparkle signing key (one-time setup)

Ice checks for updates at `https://github.com/cubbieblue16/Ice/releases/latest/download/appcast.xml` (`SUFeedURL` in `Ice/Resources/Info.plist`). That Info.plist has no `SUPublicEDKey` on purpose: upstream's key belongs to upstream's private key, and the fork's key pair has not been made yet. Until it exists, Sparkle starts normally, because the feed is HTTPS and every build is code signed, but it rejects every update. Without a key, Sparkle requires the new build to satisfy the old build's code signature, and an ad hoc signature only matches the exact build that carries it.

Mike runs this once, on his own Mac. It is never run in CI or by an agent.

1. Build Ice once so Xcode downloads Sparkle. Then run `generate_keys` from the Sparkle package in the derived data folder (`/tmp/ice-build` for `install.sh`):

   ```sh
   /tmp/ice-build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   It stores the private key in the login keychain and prints the public key.
2. Add the public key to `Ice/Resources/Info.plist`:

   ```xml
   <key>SUPublicEDKey</key>
   <string>the printed public key</string>
   ```

3. Export the private key, add it as the repository secret `SPARKLE_PRIVATE_KEY` (Settings › Secrets and variables › Actions) and delete the exported file:

   ```sh
   /tmp/ice-build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
   ```

4. Commit, then tag the release (`git tag v…` and push the tag). With the secret set, the workflow signs `Ice-27.0.zip` and attaches `appcast.xml` to the release.

You need both halves:

- **No secret:** the workflow publishes only the zip, and the update check finds no appcast.
- **Secret without a matching `SUPublicEDKey`:** `generate_appcast` leaves the zip unsigned, and the workflow stops before publishing.

A build made before step 2 has no key, so it cannot accept an update. Install the first release that has the key by hand, with `install.sh` or from the release zip. Sparkle updates in place from then on.

Developer ID signing and notarization are not set up: there is no Developer ID certificate yet. The commented TODO block in `release.yml` lists the steps.
