# ignored-directive-reproductions

A misspelled or misplaced systemd directive can be ignored with a warning while
`systemd-analyze verify` still exits 0. This repository reproduces that
behavior, shows how `--recursive-errors=` changes the exit status, and tests the
minimal CI gate from the article against its own control.

Companion to the article
[The Directive That Was Ignored](https://revisualized.com/articles/the-directive-that-was-ignored).

## Run it

Run it as an ordinary user. Nothing here needs root. Invoke the script with
`bash`, because the executable bit is not preserved in this repository.

```bash
bash ignored_directive_reproductions.sh;
```

| Option | Effect |
|---|---|
| (none) | Run every section and keep the evidence directory |
| `--clean` | Run every section and remove the evidence directory on exit |
| `--self-test` | Replace `systemd-analyze` with a stub that always succeeds and require the checks to reject it |
| `--require-runtime` | Treat a skipped section 7 as a failure |
| `--purge` | Remove every evidence directory this script created, then exit |
| `--help` | Print the usage notes from the script header |

Exit status: 0 when no check failed, 1 when a check failed, 2 on a usage or
environment error.

## Requirements

- bash 4 or newer
- systemd 250 or newer, because the script depends on `--recursive-errors=`,
  which systemd 250 introduced
- Section 7 only: a running systemd user manager (`systemctl --user` must
  answer). Without one, section 7 is skipped and reported as skipped.

## What it asserts, and where

The article's evidence comes from one build: **systemd 255
(255.4-1ubuntu8.15)** on Ubuntu 24.04.4 LTS. On that exact build, every
expectation is asserted and a mismatch fails the run.

On any other release, including other systemd 255 builds, systemd results are
recorded as observations next to the article's value, and the run reports how
many expectation-bearing checks match. Only the script's own invariants are
asserted there: the gate's usage error, its refusal when the control breaks,
and its refusal on a release before 250.

A second recorded run, on systemd 259 (259.5-0ubuntu3.4), Ubuntu 26.04.1 LTS
under WSL2, on 2026-09-24: every verifier exit status matched the article. The
three differences were diagnostic wording. For example, 255 prints
`Unknown key name 'RestartSecc' in section 'Service'` and 259 prints
`Unknown key 'RestartSecc' in section [Service]`. Section 7 ran there and read
back `Restart=no` for the typo unit against a correctly spelled control reading
`Restart=on-failure`. The missing-`WorkingDirectory=` unit ended `failed` with
`ExecMainStatus=200` (`EXIT_CHDIR`).

## What the sections cover

| Section | Content |
|---|---|
| 0 | Preflight: tools, release, and whether results are asserted or recorded |
| 1 | Default exit status for eleven fixture units |
| 2 | Which stream the diagnostic goes to, and its text |
| 3 | `--recursive-errors=no`, `one`, and `yes` for each fixture |
| 4 | Whether a warning in a referenced unit reaches the parent's exit status |
| 5 | The article's gate, copied byte for byte, plus five sabotage cases |
| 6 | The `Documentation=` check, which depends on the host's `man` |
| 7 | Optional: read the effective `Restart=` back from your user manager |

The `one` result in section 4 is explained by the systemd 255 source,
[src/analyze/analyze-verify-util.c at v255](https://github.com/systemd/systemd/blob/v255/src/analyze/analyze-verify-util.c):
under `one`, recorded warning unit names are compared with the file names given
on the command line, so a warning from a unit that is only referenced does not
change the exit status.

## What it writes

Everything goes into one directory, `/tmp/revisualized_ignored_directive.XXXXXX/`:
the fixture units, the raw stdout, stderr, and exit status of every verify
call, the gate and its controls, a transcript, and a one-line-per-check
summary. The directory is kept after the run unless `--clean` is given. The
last lines of output print its path.

**Absent paths.** The fixtures name `/opt/definitely-absent` and
`/opt/absent/app`, which must not exist. If either exists on your host, the
script substitutes equivalent absent paths inside its own run directory and
says so in the preflight and in the result.

**Section 7 user units.** Section 7 writes three unit files into
`${XDG_RUNTIME_DIR}/systemd/user/`, named
`revisualized-ignored-directive-<run suffix>-*.service`. The script refuses to
overwrite an existing file of that name and removes all three on exit. A run
killed with `kill -9`, a crash, or a power loss skips that cleanup. To remove
leftover units by hand:

```bash
runtime_unit_directory="${XDG_RUNTIME_DIR}/systemd/user";
systemctl --user stop 'revisualized-ignored-directive-*';
rm -f -- "${runtime_unit_directory}"/revisualized-ignored-directive-*.service;
systemctl --user daemon-reload;
systemctl --user reset-failed;
```

The runtime directory is also cleared at logout or reboot.

**`--purge`** removes every evidence directory this script marked, including
one that another run of it is still using. Do not run it while another run is
in progress.

## What the self-test proves

`--self-test` swaps `systemd-analyze verify` for a stub that exits 0 for every
unit and requires four targeted checks to catch it. It exercises one crude
failure mode of the checking layer. It does not prove that every check is
correct.

## What a pass means

`DEMONSTRATIONS: PASS` means the checks behaved as the article describes on
this release. It says nothing about whether any unit you deploy is correct. A
passing `systemd-analyze verify` establishes what the verifier checked, and the
article covers what it leaves unchecked.

## License

See [LICENSE](LICENSE).
