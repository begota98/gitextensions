# macOS packaging

`build-and-package.sh` automates the build and launch legs of
[`../macos-smoke-checklist.md`](../macos-smoke-checklist.md) and produces something installable:

```sh
eng/avalonia/macos/build-and-package.sh eng/avalonia/parity-evidence/P0.6/macos-$(uname -m)
```

It writes `artifacts/macos/Git Extensions.app` and `artifacts/macos/GitExtensions-<rid>.dmg`,
and leaves `summary.txt`, `launch.log` and `window.png` in the evidence directory.

Three macOS-specific constraints shape the result:

- **The runtime is bundled** (`--self-contained`). macOS has no system-wide .NET, and a
  framework-dependent apphost needs `DOTNET_ROOT`, which Finder, the Dock and Launchpad do not
  pass to a launched bundle.
- **The bundle is re-signed ad-hoc.** Assembling the tree around the ad-hoc-signed apphost
  invalidates its signature, and Apple Silicon silently refuses to launch a bundle whose
  signature does not cover the whole bundle. Launching from a terminal still works, so the
  failure only shows up from the Dock.
- **`Contents/MacOS` is a real directory**, not a symlink, and the executable lives inside the
  bundle so it keeps its icon.

The smoke launch runs with `DOTNET_ROOT` unset and `PATH` reduced to `/usr/bin:/bin`, which is
what demonstrates the bundle installs on a Mac with nothing preinstalled.

The resulting bundle is unsigned as far as Gatekeeper is concerned; a first launch needs
right-click → Open. Distribution signing requires a Developer ID and is out of scope here.

# parity-scaffolding: retained until release packaging replaces it.
