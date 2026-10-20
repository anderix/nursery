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
xplan tasks --assignee me --overdue
xplan add "Website relaunch" "Draft the launch post" --due fri --assign me --label Client
xplan set <task-id> --progress done
xplan check add <task-id> "Get sign-off from legal"
xplan bucket add "Website relaunch" Review
xplan label name "Website relaunch" 3 Blocked
```

Listings are plural nouns (`plans`, `buckets`, `labels`, `tasks`); changes to a plan, bucket, label or checklist are a singular noun and an action (`bucket rename`, `check done`); tasks themselves are `add`, `set`, `show` and `rm`. `xplan -h` lists every command and `xplan <command> -h` its flags.

A plan or bucket is named by its title or its ID, and a label by its name or its slot number (Planner offers 25 per plan). A task is named by its ID, which `xplan tasks` prints first on each line and `xplan add` prints on its own; a checklist item by the number `xplan show` prints beside it. `xplan tasks` with no plan lists the tasks assigned to you across every plan. Listings, `show` and `add` take `--json`.

Dates take `YYYY-MM-DD`, `today`, `tomorrow`, a weekday (the next one after today), `+3d` or `+2w`, and `none` clears one. `--notes -` reads a task's notes from standard input.

Planner refuses a change that does not name the version it replaces, so xplan reads each item immediately before writing it; if someone changes it in between, xplan says so and the command can be run again. Deleting a bucket through Graph leaves its tasks behind, pointing at a bucket that no longer exists, so `bucket rm` refuses a bucket that holds tasks, and with `--force` deletes the tasks first.

`set --plan` moves a task to another plan, into its first bucket unless `--bucket` names one there. Labels belong to a plan, so a move removes them and says which; `--label` on the same command applies the destination's. A plan with no buckets cannot take a task until it has one.

Creating, deleting and moving whole plans stays in the Planner web app: a plan belongs to a Microsoft 365 group, and xplan's permissions do not reach groups.
