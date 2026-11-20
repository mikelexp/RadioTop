set shell := ["bash", "-euo", "pipefail", "-c"]

version := `tr -d '[:space:]' < VERSION`
flutter := env_var_or_default("FLUTTER", `if command -v fvm >/dev/null 2>&1 && fvm flutter --version >/dev/null 2>&1; then printf 'fvm flutter'; else printf 'flutter'; fi`)
release_archive := ".release/radiotop-" + version + "-linux-x86_64.tar.gz"

default:
    @just --list

version:
    @printf 'RadioTop %s\n' "{{version}}"

[script]
check-flutter:
    #!/usr/bin/env bash
    set -euo pipefail
    fail() {
        echo "$1" >&2
        exit 127
    }
    if [[ -n "${FLUTTER:-}" ]]; then
        read -r -a flutter_command <<< "$FLUTTER"
        command -v "${flutter_command[0]}" >/dev/null 2>&1 \
            || fail "FLUTTER='$FLUTTER' was not found; set it to 'flutter' or 'fvm flutter'."
        "${flutter_command[@]}" --version >/dev/null 2>&1 \
            || fail "Flutter could not start via FLUTTER='$FLUTTER'. Install/configure a Flutter SDK and retry."
    elif command -v fvm >/dev/null 2>&1 && fvm flutter --version >/dev/null 2>&1; then
        :
    elif command -v flutter >/dev/null 2>&1 && flutter --version >/dev/null 2>&1; then
        :
    elif command -v fvm >/dev/null 2>&1; then
        fail "FVM is installed but no usable Flutter SDK is configured. Run 'fvm install' or install Flutter directly, then retry."
    elif command -v flutter >/dev/null 2>&1; then
        fail "Flutter is on PATH but could not start. Reinstall/configure the Flutter SDK and retry."
    else
        fail "RadioTop needs the Flutter SDK (which includes Dart). Install Flutter directly or install FVM and configure a Flutter SDK, then retry."
    fi

run *ARGS: check-flutter
    {{flutter}} run -d linux {{ARGS}}

set-version VERSION:
    @[[ "{{VERSION}}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must be plain semver (for example 0.9.1)" >&2; exit 1; }
    @printf '%s\n' "{{VERSION}}" > VERSION
    @sed -i -E "s/^version: .*/version: {{VERSION}}+1/" pubspec.yaml
    @sed -i -E "s/^pkgver=.*/pkgver={{VERSION}}/; s/^pkgrel=.*/pkgrel=1/; s/^sha256sums=.*/sha256sums=('SKIP')/" PKGBUILD

build: check-flutter
    {{flutter}} build linux --release --build-name "{{version}}" --build-number 1

release-archive: build
    @mkdir -p .release
    @tar -czf "{{release_archive}}" -C build/linux/x64/release bundle -C "$PWD" LICENSE radiotop.desktop radiotop.png radiotop.svg
    @archive_checksum="$(sha256sum "{{release_archive}}" | cut -d ' ' -f1)"; sed -i -E "s/^sha256sums=.*/sha256sums=('$archive_checksum')/" PKGBUILD
    @cp PKGBUILD .release/PKGBUILD
    @sha256sum "{{release_archive}}"

verify-release-tag:
    @[[ "${GITHUB_REF_NAME:-}" == "v{{version}}" ]] || { echo "Tag must match VERSION (expected v{{version}})" >&2; exit 1; }
    @grep -Fx "version: {{version}}+1" pubspec.yaml

# Push the version tag; the GitHub Actions workflow builds and publishes assets.
release-github:
    @git diff --quiet HEAD -- VERSION pubspec.yaml PKGBUILD || { echo "Commit the version changes before tagging" >&2; exit 1; }
    @git tag "v{{version}}"
    @git push github "v{{version}}"

# Called by GitHub Actions after the version tag is pushed.
publish-github: verify-release-tag release-archive
    gh release create "v{{version}}" "{{release_archive}}" --title "RadioTop v{{version}}" --generate-notes

# Publish the generated PKGBUILD to the existing AUR package repository.
[script]
aur-publish:
    #!/usr/bin/env bash
    set -euo pipefail
    release_version="$(tr -d '[:space:]' < VERSION)"
    : "${AUR_SSH_PRIVATE_KEY:?Set AUR_SSH_PRIVATE_KEY to an AUR-authorized SSH private key}"
    mkdir -p .release
    ssh-keyscan aur.archlinux.org > .release/known_hosts
    eval "$(ssh-agent -s)" >/dev/null
    trap 'ssh-agent -k >/dev/null 2>&1 || true' EXIT
    printf '%s\n' "$AUR_SSH_PRIVATE_KEY" | ssh-add - >/dev/null
    export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=$PWD/.release/known_hosts -o StrictHostKeyChecking=yes"
    rm -rf .release/aur
    git clone --depth 1 ssh://aur@aur.archlinux.org/radiotop-bin.git .release/aur
    cp .release/PKGBUILD .release/aur/PKGBUILD
    cd .release/aur
    makepkg --printsrcinfo > .SRCINFO
    git config user.name "${AUR_GIT_NAME:-RadioTop release bot}"
    git config user.email "${AUR_GIT_EMAIL:-radiotop-release@users.noreply.github.com}"
    if ! git diff --quiet; then
        git add PKGBUILD .SRCINFO
        git commit -m "Update to ${release_version}"
        git push
    else
        echo "AUR package is already up to date."
    fi

clean:
    rm -rf .release
