# xplan

Create, read, update and delete Microsoft Planner tasks from the command line.

Planner has no command-line client of its own, and its web app is slow going for anything in bulk or anything a script or an agent should do. xplan talks to Planner through Microsoft Graph with delegated permissions (`Tasks.ReadWrite` and `User.ReadBasic.All`), so it sees and changes only what the signed-in user could in Planner itself. Basic plans only: premium plans live in Dataverse, which Graph's Planner API does not reach.

## Install

```bash
./install.sh
```

It builds with Go into `~/bin`.

## Signing in

The first command run from an interactive terminal prints a device code and a URL; sign in there once. The session is cached, sealed where the operating system offers a key store, at `~/.config/excelano/planner-token.json`, and renews silently after that, so later runs work unattended. Run without a terminal and with no session, xplan refuses at once rather than waiting on a code nobody will see. `xplan auth` reports the session without starting a sign-in. Delete the cache file to sign out.

## Usage

```bash
xplan plans
xplan tasks "Website relaunch" --bucket Doing
xplan tasks --assignee me --status all
xplan add "Website relaunch" "Draft the launch post" --due 2026-11-02 --assign me --priority important
xplan set <task-id> --progress done
xplan show <task-id>
xplan rm <task-id>
```

A plan or bucket is named by its title or its ID; a task by its ID, which `xplan tasks` prints first on each line and `xplan add` prints on its own. `xplan tasks` with no plan lists the tasks assigned to you across every plan. Every command takes `--json` for output a program can read, and `xplan <command> -h` lists the command's flags.

`--notes -` reads a task's notes from standard input. Planner refuses a change to a task that does not name the version it replaces, so `set` and `rm` read the task immediately before writing it; if someone changes it in between, xplan says so and the command can be run again.
