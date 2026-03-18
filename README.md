# Spider Monorepo
![Spiderweb](Spiderweb.png)

The Spider ecosystem is a based around the Spiderweb agent 'hosted' OS,

- Spiderweb - allows any AI agent to  access a shared distributed filesystem using a filesystem RPC style approach that the agent self learn
- SpiderApp - front end gui, to interact and observe the Spiderweb
- SpiderNode - small nodes that provide new filesystems and venoms to the Spiderweb
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
