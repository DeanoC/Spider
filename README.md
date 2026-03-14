# Spider Monorepo

This repository is the umbrella repo for the Spider projects and tracks each codebase as a git submodule:

- `Spiderweb`
- `SpiderApp`
- `SpiderNode`
- `SpiderMonkey`

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
