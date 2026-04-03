# Connect a Linux Machine to Another Spiderweb

This is the supported Linux node path for Ubuntu/Debian machines with `systemd`.

Use it when you want a Linux machine to extend a remote Spiderweb, for example:

- Linux node -> macOS Spiderweb server
- Linux node -> Linux Spiderweb server

## Install

```bash
curl -fsSL https://github.com/DeanoC/Spider/releases/latest/download/install-linux.sh -o install-linux.sh
chmod +x install-linux.sh
sudo ./install-linux.sh
```

Then run:

```bash
spider
```

Choose:

- `Connect This Linux Machine`

## Pairing models

The guided flow supports both:

- invite token
- request / approve

The default published node shape is:

- `Workspace Shell` terminal enabled
- no broad host filesystem share
- optional explicit export paths you choose during setup

## Non-interactive commands

Install scaffolding:

```bash
spider local-node install
```

Connect with an invite:

```bash
spider local-node connect \
  --control-url ws://your-spiderweb-host:18790/ \
  --control-auth-token <server-access-token> \
  --invite-token <invite-token>
```

Connect with request / approve:

```bash
spider local-node connect \
  --control-url ws://your-spiderweb-host:18790/ \
  --control-auth-token <server-access-token> \
  --request-approval
```

Optional extras:

```bash
spider local-node connect \
  --control-url ws://your-spiderweb-host:18790/ \
  --control-auth-token <server-access-token> \
  --request-approval \
  --node-name build-box \
  --export /srv/repo \
  --export /var/data
```

Most Spiderweb hosts will require a server access token for control-plane pairing. Use the same Spiderweb access token you already use to connect from SpiderApp or the `spider` CLI.

Status and removal:

```bash
spider local-node status
spider local-node remove
```

## Server-side approval commands

Run these on the Spiderweb host:

```bash
spider node invite-create
spider node pending
spider node approve <request-id>
spider node deny <request-id>
```

On macOS, run those commands from the same `spider` CLI you use against your local Spiderweb server.

The invite flow prints the Linux connect command and reminds you to add `--control-auth-token <server-access-token>` when the remote Spiderweb requires auth.

## What status shows

- whether `spider-node.service` is installed and active
- connected control URL
- pairing state
- node id or pending request id
- configured export paths
- whether terminal is published
