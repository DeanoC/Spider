# Spider Monorepo
![Spiderweb](Spiderweb.png)

The Spider ecosystem is a based around the Spiderweb agent 'hosted' OS,

- Spiderweb -  A agent first distributed OS that any agent can use with just basic filesystem tools
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
