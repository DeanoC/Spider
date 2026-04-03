# Host Spiderweb on Linux

This is the supported Linux operator path for Ubuntu/Debian machines with `systemd`.

## Install

```bash
curl -fsSL https://github.com/DeanoC/Spider/releases/latest/download/install-linux.sh -o install-linux.sh
chmod +x install-linux.sh
sudo ./install-linux.sh
```

If you already have a local archive:

```bash
sudo ./install-linux.sh --archive ./spider-suite-linux-aarch64.tar.gz
```

The installer stages:

- `spider`
- `spiderweb`
- `spiderweb-config`
- `spiderweb-fs-node`
- shared runtime assets under `/usr/local/share`

Then it launches `spider` so you can choose the job for this machine.

## Guided path

Run:

```bash
spider
```

Choose:

- `Host Spiderweb Here`

That flow will:

- initialize Spiderweb config if needed
- install or update the `spiderweb.service` unit
- enable and start the service
- ensure access auth exists
- print the server URL and next step

## Non-interactive commands

```bash
spider server install
spider server status
spider server doctor
spider server remove
```

Useful examples:

```bash
spider server install --bind 0.0.0.0 --port 18790
spider server status
spider server doctor
```

## What “doctor” checks

- service installed
- service active
- auth present
- runtime assets present
- server bind is remote-usable or local-only
- local node binary present

## Next step

Once the server is ready, create or use a workspace from the same CLI:

```bash
spider workspace create "Linux Workspace"
```
