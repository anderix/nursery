# boxes-remote

View one machine's Gnome Boxes (libvirt) virtual machines from another machine
over SSH. Gnome Boxes has no built-in remote access, so these scripts wire it up
end to end: prepare the host that owns the VMs, then set up each client that
wants to see them, and every VM lands in your app grid as a normal launcher.

There are two sides. On the **host** (the machine the VMs live on) you run
`boxes-host-setup` once. On each **client** (a machine you sit at) you run
`boxes-remote-setup`. After that, opening a VM is just clicking its launcher.

## Install

```bash
./install.sh
```

Copies the four commands into `~/bin`. The runtime dependencies
(`virt-viewer`, `libvirt-clients`, `virt-manager`) are installed for you by
`boxes-remote-setup` on the client; on the host you only need
`libvirt-clients`.

## Setup

On the host that owns the VMs:

```bash
boxes-host-setup
```

Gnome Boxes binds each VM's SPICE display to `listen='none'`, which can't be
reached over `qemu+ssh`. `boxes-host-setup` rewrites every VM to listen on
loopback (`127.0.0.1`) and enables user lingering so the session libvirt answers
over SSH even when no one is logged in at the host. Restart any VM that was
running for the new display to take effect. Pass VM names to fix only some;
with no arguments it fixes them all.

On each client, point it at the host and run the one-shot setup:

```bash
export BOXES_REMOTE_HOST=you@hostname.local   # put this in ~/.bashrc
boxes-remote-setup
```

That installs the viewer tools, sets up passwordless SSH to the host, verifies
the libvirt connection, and generates a desktop launcher per VM. You can also
pass the host explicitly: `boxes-remote-setup you@hostname.local`.

## The commands

| Command | Side | What it does |
|---|---|---|
| `boxes-host-setup` | host | Fix VM displays for remote viewing and enable lingering |
| `boxes-remote-setup` | client | One-shot: tools, SSH, verify, generate launchers |
| `gen-vm-launchers` | client | (Re)generate the per-VM desktop launchers |
| `run-remote-vm` | client | Start a VM if needed and open its console (what the launchers call) |

`BOXES_REMOTE_HOST` supplies the default `USER@HOST` for the client commands, so
you set it once instead of typing it each time. Every command still takes an
explicit host argument when you want to target a different machine.
