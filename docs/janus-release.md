# Janus release runbook

The installer downloads a prebuilt ARM64 Janus bundle for native H.264 on the
U1. The maintainer builds the bundle, tests it on the printer, and publishes
the exact archive that passed. Docker runs on the build machine.

## 1. Choose a release revision

Start a release when the Janus version, a bundled dependency, or the build
changes. Use `janus-u1-vX.Y.Z-rN` as the tag. Increment the revision when
rebuilding the same Janus version. For example, a dependency update for Janus
1.4.3 could become `janus-u1-v1.4.3-r2`.

Review the upstream Janus commit and source checksum in
[`build-u1-janus.sh`](../scripts/build-u1-janus.sh). The script uses a
digest-pinned ARM64 Debian image and records the exact Debian package versions
it resolves. Review changes in the package manifest before approving a build.
Every change to the archive bytes gets a new revision.

## 2. Build and prepare a draft

From the repository root on a machine with Docker, use an empty output directory:

```bash
out=$(mktemp -d /tmp/obico-janus-release.XXXXXX)
bash scripts/build-u1-janus.sh "$out" &&
bash scripts/collect-janus-sources.sh "$out" &&
(cd "$out" && sha256sum -c obico-janus-u1-aarch64.tar.gz.sha256)
```

The build must start Janus in a clean ARM64 container and load the Streaming
and WebSockets plugins. Review `BUILD-INFO` and `PACKAGES` inside the runtime
archive. Check that the dependency source archive covers the package versions
in `PACKAGES`.

Create a draft prerelease using the chosen tag and the reviewed build commit.
Attach these four files:

| Asset | Contents |
| --- | --- |
| `obico-janus-u1-aarch64.tar.gz` | Private runtime, libraries, licenses, and build and package manifests |
| `obico-janus-u1-aarch64.tar.gz.sha256` | SHA-256 of the runtime archive |
| `janus-X.Y.Z-source.tar.gz` | The exact Janus source used for the build |
| `obico-janus-u1-debian-sources.tar` | The exact source packages for the bundled Debian libraries |

Set `JANUS_RELEASE_URL` and `JANUS_RELEASE_SHA256` in
[`obico-install.sh`](../obico-install.sh) on the installer PR to this draft's
tag and checksum. Verify the uploaded runtime asset's digest against the pin.
Keep the candidate archive for the printer test.

## 3. Test the exact candidate on the U1

Use a U1 with Paxx Extended Firmware and a self-hosted Obico server. Back up
the config and keep the printer idle for operations that restart Moonraker.
Copy the installer from the PR and the runtime archive from the draft to
`/tmp` on the printer. The installer verifies the archive against its pinned
checksum.

For an existing linked setup, run:

```bash
cd /tmp
bash obico-install.sh backup &&
bash obico-install.sh update --janus-bundle /tmp/obico-janus-u1-aarch64.tar.gz &&
bash obico-install.sh doctor
```

Record the installer commit, archive SHA-256, printer firmware version, and
results in the PR. All of these checks should pass:

1. The same printer returns online without linking again. When updating an
   already-enabled native video setup, the linked config matches its backup.
2. `doctor` verifies the pinned Janus runtime and can reach the U1's native
   H.264 endpoint.
3. Obico shows live video. After playback starts, compare visible motion
   against Fluidd for a minute. Obico should remain within two seconds of
   Fluidd and the delay should stay steady.
4. Run `bash obico-install.sh restore` twice, allowing the feed to start after
   each restart. Each time, confirm one Obico app, one Janus process from
   `/userdata/obico-janus/runtime`, and one FFmpeg sender for the U1 stream:

   ```bash
   pgrep -f '[m]oonraker_obico[.]app'
   for pid in $(pgrep -f '[j]anus.*--configs-folder'); do
     readlink "/proc/$pid/exe"
   done
   pgrep -f '[f]fmpeg.*stream[.]h264'
   ```

5. Run `bash tests/installer.sh` and require the PR's CI check to pass. The
   suite covers fresh install, config preservation, a rejected archive,
   rollback, and uninstall alongside a separate Janus installation. For the
   first public release, also test a fresh install on a clean U1 setup if one
   is available.

Keep a failed candidate unpublished. Fix the issue and assign a new revision
if the archive changes.

## 4. Publish and verify the installer download

Publish the tested draft with its four assets. Check the public download URL
without GitHub credentials and verify the digest against the installer pin.
Then verify that `update --native-video` downloads the release onto a test
setup without a cached runtime. Merge the installer PR after the public
download and CI pass.

Keep previous releases available. If a public bundle regresses, restore the
previous release URL and checksum in the installer and verify that an update
installs that revision. The runtime, archive, and digest can stay with their
original release tags.

## Planned GitHub Actions workflow

The build scripts currently run from a maintainer's computer. GitHub Actions
runs the installer regression tests. Add release automation as a manually
triggered workflow with these boundaries:

1. A maintainer starts **Build Janus bundle** from the default branch with a
   new release tag. A read-only job on a GitHub ARM64 runner uses the
   checked-out build scripts to build, smoke-test, and collect the sources.
2. A separate job with release write permission checks the checksum, refuses
   a tag that already has a release, and attaches the four files to a new
   draft. Serialize draft creation by tag. The workflow reports the tag,
   digest, and draft URL.
3. The maintainer tests those same files on a U1 and publishes the draft after
   the checks above pass. Publication and the installer checksum change remain
   explicit review steps.

[GitHub manual workflow documentation](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
