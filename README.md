# Spider Monorepo
![Spiderweb](Spiderweb.png)

The Spider ecosystem is a based around the Spiderweb agent 'hosted' OS,

- Spiderweb -  A agent first distributed OS that any agent can use with just basic filesystem tools
- SpiderApp - front end gui, to interact and observe the Spiderweb
- SpiderNode - small nodes that provide new filesystems and venoms to the Spiderweb
- SpiderVenoms - first-party capability venoms and managed local bundle releases
- SpiderVenomRegistry - signed static registry metadata for published venom bundles
- SpiderMonkey - custom research AI agent that is designed specifically for Spiderweb


## Clone

```bash
git clone --recurse-submodules <this-repo-url>
```

If you already cloned the repo without submodules:

```bash
git submodule update --init --recursive
```

## Update submodules

```bash
git submodule update --remote --merge
```

## Packaging

Product-local packaging stays inside each product repo:

- `Spiderweb/platform/macos/scripts/package-spiderweb-macos-release.sh`
- `SpiderApp/scripts/package-macos-app.sh`

The parent repo now owns suite-level macOS packaging:

```bash
./scripts/package-spider-suite-macos.sh
```

That script orchestrates the existing Spiderweb and SpiderApp packagers, re-signs the staged SpiderApp bundle for distribution, builds a top-level `SpiderSuite-...pkg`, stages everything together under `dist/`, writes a suite manifest, renders `RELEASE_NOTES.md`, and zips the combined bundle.

The parent repo now also owns the canonical Linux suite archive:

```bash
./scripts/package-spider-suite-linux.sh
```

That Linux archive bundles:

- `spider` as the operator CLI/TUI
- `spiderweb` and `spiderweb-config`
- `spiderweb-fs-node`
- shared runtime assets under `share/`

## Linux

The supported Linux path is Ubuntu/Debian with `systemd`, using `spider` as the primary operator surface.

Install from a published archive with:

```bash
sudo ./install-linux.sh
```

Then run:

```bash
spider
```

The guided Linux home offers exactly three jobs:

- `Host Spiderweb Here`
- `Connect This Linux Machine`
- `Status / Repair`

Further docs:

- [Host Spiderweb on Linux](docs/linux-host-spiderweb.md)
- [Connect a Linux machine to another Spiderweb](docs/linux-connect-node.md)

For Linux node pairing on a macOS-hosted Spiderweb, use the same `spider` CLI on the Mac host for:

- `spider node invite-create`
- `spider node pending`
- `spider node approve <request-id>`
- `spider node deny <request-id>`
