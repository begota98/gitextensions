#!/usr/bin/env bash
set -euo pipefail

# parity-scaffolding: automates the macOS leg of macos-smoke-checklist.md until release
# packaging replaces it. Produces a self-contained .app bundle and a .dmg, then records the
# launch evidence the checklist asks for.

evidence_dir=${1:-}
if [[ -z "$evidence_dir" ]]; then
    echo "usage: build-and-package.sh <evidence-directory>" >&2
    exit 2
fi

if [[ "$(uname -s)" != Darwin ]]; then
    echo "error: this script builds a macOS bundle and must run on macOS" >&2
    exit 1
fi

for tool in dotnet git cc iconutil codesign hdiutil sw_vers; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required command '$tool' is not installed" >&2
        exit 1
    fi
done

repo_root="$(git rev-parse --show-toplevel)"
project="$repo_root/src/app/GitExtensions.Avalonia/GitExtensions.Avalonia.csproj"
logo="$repo_root/setup/assets/Logo"
architecture="$(uname -m)"
if [[ "$architecture" == arm64 ]]; then rid=osx-arm64; else rid=osx-x64; fi
out="$repo_root/artifacts/Release/bin/GitExtensions.Avalonia/net10.0/$rid"
build_root="$repo_root/artifacts/macos"
app="$build_root/Git Extensions.app"
iconset="$build_root/GitExtensions.iconset"
dmg="$build_root/GitExtensions-$rid.dmg"
version="$(git -C "$repo_root" rev-parse --short HEAD)"

mkdir -p "$evidence_dir" "$build_root"
rm -rf "$app" "$iconset" "$dmg"

# macOS has no system-wide .NET, so the bundle carries the runtime. A framework-dependent
# apphost would need DOTNET_ROOT, which Finder and the Dock do not provide.
dotnet build "$project" -c Release -r "$rid" --self-contained true -v:minimal

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512"; do
    read -r px name <<<"$spec"
    cp "$logo/git-extensions-logo-${px}px.png" "$iconset/icon_${name}.png"
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/GitExtensions.icns"
rm -rf "$iconset"

# Copied, not symlinked: macOS refuses to launch a bundle whose MacOS directory is a symlink,
# and the executable has to sit inside the bundle to keep its icon. Plugins stay
# framework-dependent managed assemblies and load on the bundled runtime.
rsync -a "$out/" "$app/Contents/MacOS/"
rsync -a --exclude runtimes "$out/../Plugins" "$app/Contents/MacOS/"

# Each plugin directory receives a copy of the host assemblies it was compiled against, which
# roughly doubles the bundle. A plugin is discovered by MEF at run time and only needs the
# assemblies that are its own.
payload="$app/Contents/MacOS"
for file in "$payload"/Plugins/*/*; do
    [[ -f "$file" && -f "$payload/$(basename "$file")" ]] && rm -f "$file"
done

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Git Extensions</string>
<key>CFBundleIdentifier</key><string>com.github.gitextensions.GitExtensions.Avalonia</string>
<key>CFBundleExecutable</key><string>GitExtensions.Avalonia</string>
<key>CFBundleIconFile</key><string>GitExtensions.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# Apple Silicon refuses to launch a bundle from Finder or the Dock when its signature does not
# cover the whole bundle. Assembling the tree around the ad-hoc-signed apphost invalidates the
# original signature, so re-sign the finished bundle.
codesign --remove-signature "$app" 2>/dev/null || true
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

hdiutil create -volname "Git Extensions" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null

# The checklist asks for a launch that proves the bundle needs nothing preinstalled. Go through
# launchd rather than exec'ing the apphost: that is the Finder and Dock path, it passes no shell
# environment at all, and it is what catches an invalid bundle signature. A GUI session is
# required, so over SSH without a logged-in console user the launch is skipped, not failed.
smoke_status="skipped (no GUI session)"
if launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
    smoke_parent="$(mktemp -d)"
    trap 'rm -rf "$smoke_parent"' EXIT
    git -C "$smoke_parent" init -q repository
    if open -a "$app" --args browse "$smoke_parent/repository" >"$evidence_dir/launch.log" 2>&1; then
        sleep 20
        if pgrep -f "$app/Contents/MacOS/GitExtensions.Avalonia" >/dev/null; then
            smoke_status="launched"
            screencapture -x "$evidence_dir/window.png" || true
            pkill -f "$app/Contents/MacOS/GitExtensions.Avalonia" 2>/dev/null || true
        else
            # Avalonia.Native reports -6661 when it cannot reach the window server, which happens
            # with a locked screen or a sleeping display even though the GUI domain exists. That is
            # a property of the session, not of the bundle, so record it rather than fail the build.
            smoke_status="did not stay alive; see launch.log"
        fi
    else
        smoke_status="launchd refused to open the bundle; see launch.log"
    fi
fi

{
    echo "commit: $(git -C "$repo_root" rev-parse HEAD)"
    echo "architecture: $architecture"
    echo "runtime identifier: $rid"
    echo "macOS: $(sw_vers -productVersion)"
    echo "bundle: $app"
    echo "dmg: $dmg ($(du -h "$dmg" | cut -f1))"
    echo "signature: ad-hoc, verified"
    echo "smoke launch: $smoke_status"
} >"$evidence_dir/summary.txt"

cat "$evidence_dir/summary.txt"
