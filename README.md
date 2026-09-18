# (unofficial) T3 Code Nix flake

Installs the upstream T3 Code desktop application from either the latest stable release or the latest nightly release.

```sh
nix profile install .#latest .#nightly
```

Both packages can be installed in the same profile. Launch stable with `t3code` and nightly with `t3code-nightly`.

Run without installing:

```sh
nix run .#latest
nix run .#nightly
```

The default package and `t3code` alias point to `latest`; `t3code-nightly` aliases `nightly`. Supported systems are `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin` (Can't test Darwin!).

Stable uses T3 Code's normal state directories. The nightly launcher isolates its configuration, local database, logs, Electron user data, and generated desktop integration under `~/.t3-nightly`, `~/.config/t3code-nightly`, and `~/.local/share/t3code-nightly` on Linux. On macOS its Electron profile is additionally isolated as `~/Library/Application Support/t3code-nightly` (Hopefully). Auto-update is disabled for both Nix-managed channels by the package wrappers so installed files remain managed by Nix.

`scripts/update.sh` refreshes `versions.json`. The GitHub Actions updater runs hourly and commits changes when upstream publishes a new stable or nightly build.
