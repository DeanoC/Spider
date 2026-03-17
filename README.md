# Spider Monorepo


The Spider ecosystem is a based around the Spiderweb agent 'hosted' OS,

- Spiderweb allows any AI agent to  access a shared distributed filesystem using a filesystem RPC style approach that the agent self learn
- SpiderApp is a front end gui, to interact and observe the Spiderweb
- SpiderNode is small nodes that provide new filesystems and venoms to the Spiderweb
- SpiderMonkey is a custom AI agent that is designed specifically for Spiderweb with advanced context and memory systems designed in the filesystem RPC style Spider supports.

![Spiderweb](Spiderweb.png)

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
