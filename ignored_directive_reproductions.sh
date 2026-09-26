#!/usr/bin/env bash
# ignored_directive_reproductions.sh
# Reproduces the verifier observations behind "The Directive That Was Ignored"
# and optionally demonstrates the manager's effective property read-back and the
# runtime consequence of a missing WorkingDirectory=.
# https://revisualized.com/articles/the-directive-that-was-ignored
#
# Runs as an ordinary user. Nothing needs root: sections 1 through 6 use
# systemd-analyze verify, which needs no running manager, and section 7 uses
# your own user manager (systemctl --user), not the system one.
#
# Apart from section 7's temporary user units, described below, every file the
# script writes goes into one run directory under /tmp:
#   /tmp/revisualized_ignored_directive.XXXXXX/
#     fixtures/      the unit files under test, readable after the run
#     raw/           command line, stdout, stderr, and exit status of every
#                    verify call
#     gate/          the copied gate, its active control, the sabotage controls,
#                    the leading-dash unit, and the captured gate output
#     stub-249/      the systemd 249 version stub, built in section 5
#     stub-always-ok/  the always-success verifier, in --self-test only
#     transcript.log everything printed to the terminal
#     summary.txt    one line per check, with its result
#     fixture-sha256.txt  optional, written where sha256sum, find and sort exist:
#                    a checksum of every .service file under fixtures/; gate
#                    controls and user units are outside it
# Section 7 also writes three unit files into your own user manager's runtime
# directory. Their names carry this run's mktemp suffix, the script separately
# refuses to run if a file of that name already exists, and the exit trap
# removes them.
# The run directory is kept so you can inspect the evidence. The last lines of
# output print its path and the command that removes it.
#
# Usage:
#   bash ignored_directive_reproductions.sh              run everything, keep results
#   bash ignored_directive_reproductions.sh --clean      run everything, remove results on exit
#   bash ignored_directive_reproductions.sh --self-test  negative control (see below)
#   bash ignored_directive_reproductions.sh --purge      remove this script's run directories and exit
#     (--purge removes every run directory this script marked, including one that
#     a concurrent run of it is still using)
#   bash ignored_directive_reproductions.sh --require-runtime  fail if section 7 cannot run
#
# Exit status: 0 when no check failed, including when section 7 was skipped;
# 1 when a check failed; 2 on a usage or environment error. Pass
# --require-runtime when a skipped section 7 should be an error.
#
# --self-test swaps systemd-analyze for a stub that reports success for every
# unit and requires the assertion layer to reject that condition. It exercises
# one crude failure mode, not every way a check could be wrong. A checker that
# has only ever passed has been demonstrated, not tested.
set -uo pipefail;
# Diagnostic text is part of the evidence; pin the message locale.
export LC_ALL=C;

MODE=run;
CLEAN=0;
REQUIRE_RUNTIME=0;
RUNTIME_STATUS=not-attempted;
MODE_SET=0;
set_mode() {
  if [ "${MODE_SET}" -ne 0 ]; then
    echo "ERROR: mode options cannot be repeated or combined: ${1}" >&2;
    exit 2;
  fi;
  MODE="${1}";
  MODE_SET=1;
};
for argument in "${@}"; do
  case "${argument}" in
    --clean)
      CLEAN=1;;
    --require-runtime)
      REQUIRE_RUNTIME=1;;
    --self-test)
      set_mode self-test;;
    --purge)
      set_mode purge;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${0}";
      exit 0;;
    *)
      echo "ERROR: unknown argument: ${argument} (try --help)" >&2;
      exit 2;;
  esac;
done;

RUN_DIRECTORY_PREFIX=/tmp/revisualized_ignored_directive;

# ----- 0. Preflight -----------------------------------------------------------
# Commands sections 1 to 6 need, checked before anything runs. systemctl and the
# sleep command belong to the optional section 7 and are detected there.
# /bin/sleep is checked below because every fixture's ExecStart= names it.
# Host-inspection commands (man, dpkg-query, dpkg-divert) are detected at use.
# The gate from the article adds dirname; the version stubs add sh.
REQUIRED_COMMANDS=(awk bash cat chmod cp date dirname grep head id mkdir mktemp mv ps rm sed sh systemd-analyze tee touch tr uname wc);
preflight() {
  local missing_commands=() command_name;
  if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "ERROR: bash 4 or newer is required (associative arrays); found ${BASH_VERSION:-unknown}" >&2;
    exit 2;
  fi;
  for command_name in "${REQUIRED_COMMANDS[@]}"; do
    command -v "${command_name}" > /dev/null 2>&1 || missing_commands+=("${command_name}");
  done;
  if [ "${#missing_commands[@]}" -gt 0 ]; then
    echo "ERROR: required commands not found: ${missing_commands[*]}" >&2;
    exit 2;
  fi;
  if [ ! -x /bin/sleep ]; then
    echo "ERROR: /bin/sleep is missing or not executable; every fixture's ExecStart= names it" >&2;
    exit 2;
  fi;
  if [ ! -d /tmp ] || [ ! -w /tmp ]; then
    echo "ERROR: /tmp is missing or not writable; the run directory lives there" >&2;
    exit 2;
  fi;
};

if [ "${MODE}" = self-test ] && [ "${CLEAN}" -eq 1 ]; then
  echo "ERROR: --self-test and --clean cannot be combined: a failed self-test needs its evidence kept" >&2;
  exit 2;
fi;
if [ "${MODE}" = self-test ] && [ "${REQUIRE_RUNTIME}" -eq 1 ]; then
  echo "ERROR: --self-test and --require-runtime cannot be combined: section 7 never runs under the stub" >&2;
  exit 2;
fi;
if [ "${MODE}" = purge ] && { [ "${REQUIRE_RUNTIME}" -eq 1 ] || [ "${CLEAN}" -eq 1 ]; }; then
  echo "ERROR: --purge takes no other options" >&2;
  exit 2;
fi;

if [ "${MODE}" = purge ]; then
  # Purging only removes directories this script marked, so it needs none of the
  # demonstration's prerequisites.
  for command_name in id rm; do
    command -v "${command_name}" > /dev/null 2>&1 || { echo "ERROR: required command not found: ${command_name}" >&2; exit 2; };
  done;
  found=0;
  purge_failed=0;
  for candidate_directory in "${RUN_DIRECTORY_PREFIX}".*; do
    if [ -d "${candidate_directory}" ] && [ -O "${candidate_directory}" ] && [ -f "${candidate_directory}/.ignored_directive_run" ]; then
      if rm -rf -- "${candidate_directory}"; then
        echo "removed ${candidate_directory}";
        found=1;
      else
        echo "ERROR: could not remove ${candidate_directory}" >&2;
        purge_failed=1;
      fi;
    fi;
  done;
  [ "${found}" -eq 1 ] || echo "no earlier run directories owned by $(id -un) under /tmp";
  if [ "${purge_failed}" -ne 0 ]; then
    exit 2;
  fi;
  exit 0;
fi;

preflight;
RUN_DIRECTORY="$(mktemp -d "${RUN_DIRECTORY_PREFIX}.XXXXXX")" || { echo "ERROR: cannot create a run directory under /tmp" >&2; exit 2; };
mkdir -p "${RUN_DIRECTORY}/fixtures" "${RUN_DIRECTORY}/raw" "${RUN_DIRECTORY}/gate/controls" || { rm -rf -- "${RUN_DIRECTORY}"; exit 2; };
touch "${RUN_DIRECTORY}/.ignored_directive_run" || { rm -rf -- "${RUN_DIRECTORY}"; exit 2; };
# The article's fixtures name /opt paths that must be absent. Where a host has
# them, semantically equivalent absent paths beneath the run directory replace
# those exact strings, and every report says which was used.
# The missing dependency carries this run's suffix to minimize collision with
# units elsewhere in the verifier's search path.
MISSING_DEPENDENCY="revisualized-ignored-directive-${RUN_DIRECTORY##*.}-definitely-absent.service";
ABSENT_DIRECTORY=/opt/definitely-absent;
ABSENT_BINARY=/opt/absent/app;
PATHS_LOCAL=no;
if [ -e "${ABSENT_DIRECTORY}" ] || [ -L "${ABSENT_DIRECTORY}" ] || [ -e "${ABSENT_BINARY}" ] || [ -L "${ABSENT_BINARY}" ]; then
  ABSENT_DIRECTORY="${RUN_DIRECTORY}/absent/working_directory";
  ABSENT_BINARY="${RUN_DIRECTORY}/absent/app";
  PATHS_LOCAL=yes;
fi;

# Host state this script creates outside the run directory: only section 7's
# user units. They are registered here and removed by the single exit trap.
USER_UNITS=();
USER_UNIT_DIRECTORY="";
# Invoked only by the EXIT trap below, which shellcheck cannot trace.
# shellcheck disable=SC2317,SC2329
CLEANUP_DONE=0;
# Invoked only by the EXIT trap below, which shellcheck cannot trace.
# shellcheck disable=SC2317,SC2329
cleanup() {
  local unit;
  if [ "${CLEANUP_DONE}" -ne 0 ]; then
    return;
  fi;
  CLEANUP_DONE=1;
  if [ "${#USER_UNITS[@]}" -gt 0 ]; then
    for unit in "${USER_UNITS[@]}"; do
      systemctl --user stop "${unit}" > /dev/null 2>&1 || echo "WARNING: could not stop ${unit} during cleanup" >&2;
      systemctl --user reset-failed "${unit}" > /dev/null 2>&1;
      rm -f -- "${USER_UNIT_DIRECTORY}/${unit}" || echo "WARNING: could not remove ${USER_UNIT_DIRECTORY}/${unit}" >&2;
    done;
    systemctl --user daemon-reload > /dev/null 2>&1 || echo "WARNING: user daemon-reload failed during cleanup" >&2;
  fi;
  if [ "${CLEAN}" -eq 1 ]; then
    rm -rf -- "${RUN_DIRECTORY}";
  fi;
};
# Invoked only by the signal traps below, which shellcheck cannot trace. It sets
# an exit status and lets the EXIT trap do the single cleanup.
# shellcheck disable=SC2317,SC2329
on_signal() {
  case "${1}" in
    INT)
      exit 130;;
    TERM)
      exit 143;;
  esac;
};
trap cleanup EXIT;
trap 'on_signal INT' INT;
trap 'on_signal TERM' TERM;

exec > >(tee "${RUN_DIRECTORY}/transcript.log") 2>&1;

OK=0; FAILURES=0; OBSERVED=0; OBSERVED_MATCHING=0; OBSERVED_DIFFERING=0; SKIPS=0; SELFTEST_MARKERS=0;
# die() must never call record(): record() calls die() when the summary write
# fails, and the pair would recurse.
record() { printf '%s\t%s\n' "${1}" "${2}" >> "${RUN_DIRECTORY}/summary.txt" || die "cannot write ${RUN_DIRECTORY}/summary.txt"; };
selftest_marker() {
  if [ "${MODE}" = self-test ]; then
    SELFTEST_MARKERS=$((SELFTEST_MARKERS + 1));
    echo "    rejected  the stub was caught: ${1}";
    record SELFTEST "${1}";
  fi;
};
# expect LABEL EXPECTED OBSERVED [always]
# On the exact evidence build every expectation is asserted. Elsewhere only those
# marked "always" are; the rest are printed next to the article's value.
expect() {
  if [ "${ASSERT}" -ne 1 ] && [ "${4:-}" != always ]; then
    OBSERVED=$((OBSERVED + 1));
    if [ "${2}" = "${3}" ]; then
      OBSERVED_MATCHING=$((OBSERVED_MATCHING + 1));
      echo "    observed  ${1}: [${3}], matching the article";
      record OBSERVED "${1}: [${3}], matching the article";
    else
      OBSERVED_DIFFERING=$((OBSERVED_DIFFERING + 1));
      echo "    observed  ${1}: [${3}] (the article recorded [${2}] on systemd 255)";
      record OBSERVED "${1}: [${3}], article [${2}]";
    fi;
    return;
  fi;
  if [ "${2}" = "${3}" ]; then
    OK=$((OK + 1));
    echo "    ok        ${1}: ${3}";
    record OK "${1}: ${3}";
  else
    FAILURES=$((FAILURES + 1));
    echo "    FAIL      ${1}: expected [${2}], observed [${3}]";
    record FAIL "${1}: expected [${2}], observed [${3}]";
  fi;
};
die() {
  echo "ERROR: ${*}" >&2;
  exit 2;
};
skip() {
  SKIPS=$((SKIPS + 1));
  echo "    skipped   ${1}";
  record SKIP "${1}";
};
banner() {
  echo;
  echo "==================================================================";
  echo "${1}";
  echo "==================================================================";
};
explain() { echo "  ${*}"; };

# Runs systemd-analyze verify, keeps stdout, stderr, and exit status under raw/,
# and stores the status in VERIFY_EXIT_STATUS, which callers read directly. The tag names
# the files. Call it directly, never through command substitution, so a die()
# inside it can end the whole run.

VERIFY_EXIT_STATUS=;
verify() {
  local tag="${1}"; shift;
  local base="${RUN_DIRECTORY}/raw/${tag}";
  [ -e "${base}.command" ] && die "duplicate verify tag: ${tag}";
  { printf '%q ' systemd-analyze verify "${@}"; printf '\n'; } > "${base}.command" || die "cannot record the command for ${tag}";
  : > "${base}.stdout" || die "cannot create ${base}.stdout";
  : > "${base}.stderr" || die "cannot create ${base}.stderr";
  systemd-analyze verify "${@}" > "${base}.stdout" 2> "${base}.stderr";
  VERIFY_EXIT_STATUS=${?};
  printf '%s\n' "${VERIFY_EXIT_STATUS}" > "${base}.exit" || die "cannot record the exit status for ${tag}";
};

# Recorded before any PATH change, so a stub can never become "the real one".
REAL_ANALYZE="$(command -v systemd-analyze)";
if [ "${MODE}" = self-test ]; then
  mkdir -p "${RUN_DIRECTORY}/stub-always-ok" || die "cannot create the always-success stub directory";
  cat > "${RUN_DIRECTORY}/stub-always-ok/systemd-analyze" <<STUB || die "cannot write the always-success stub"
#!/bin/sh
if [ "\${1}" = --version ]; then exec "${REAL_ANALYZE}" --version; fi
exit 0
STUB
  chmod +x "${RUN_DIRECTORY}/stub-always-ok/systemd-analyze" || die "cannot make the always-success stub executable";
  PATH="${RUN_DIRECTORY}/stub-always-ok:${PATH}";
  [ "$(command -v systemd-analyze)" = "${RUN_DIRECTORY}/stub-always-ok/systemd-analyze" ] || die "the always-success stub is not first in PATH";
fi;

banner "0. Preflight: this host, this release, and what can be asserted";
explain "Every command the script always needs was found. Optional host-inspection";
explain "commands (man, dpkg-query, dpkg-divert) are reported below if present.";
explain "Environment:";
EVIDENCE_VERSION="systemd 255 (255.4-1ubuntu8.15)";
VERSION_LINE="$(systemd-analyze --version | head -1)";
VERSION="$(printf '%s\n' "${VERSION_LINE}" | awk '{ print $2 }')";
case "${VERSION}" in
  ''|*[!0-9]*)
    echo "ERROR: cannot read the systemd version from systemd-analyze --version" >&2;
    exit 2;;
esac;
if [ "${VERSION}" -lt 250 ]; then
  echo "ERROR: systemd ${VERSION} predates --recursive-errors= (added in 250); nothing here can run" >&2;
  exit 2;
fi;
PID1="$(ps -p 1 -o comm= | tr -d ' ')";
explain "  run directory:   ${RUN_DIRECTORY}";
explain "  user:            $(id -un) (uid $(id -u))";
explain "  systemd:         ${VERSION_LINE}";
if command -v dpkg-query > /dev/null 2>&1; then
  explain "  systemd package: $(dpkg-query -W -f '${Version}' systemd 2> /dev/null || echo n/a)";
fi;
explain "  os:              $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2> /dev/null | tr -d '"')";
explain "  kernel:          $(uname -sr)";
explain "  missing unit:    ${MISSING_DEPENDENCY} (the absent-dep fixture requires it)";
explain "  pid 1:           ${PID1}";
explain "  started:         $(date -u '+%Y-%m-%dT%H:%M:%SZ')";
if [ -n "${SYSTEMD_UNIT_PATH:-}" ]; then
  explain "  SYSTEMD_UNIT_PATH was set to ${SYSTEMD_UNIT_PATH} and has been unset, so verification";
  explain "  uses this host's default unit search path";
  unset SYSTEMD_UNIT_PATH;
fi;
if [ "${PATHS_LOCAL}" = yes ]; then
  explain "  absent paths:    run-local, because this host has the article's /opt paths";
  explain "                   WorkingDirectory=${ABSENT_DIRECTORY}";
  explain "                   ExecStart=${ABSENT_BINARY}";
else
  explain "  absent paths:    the article's, ${ABSENT_DIRECTORY} and ${ABSENT_BINARY}";
fi;
if [ "$(id -u)" -eq 0 ]; then
  explain "  note: running as root is unnecessary. Section 7 uses your own user manager,";
  explain "        which root's sudo session usually lacks, so it will likely be skipped.";
fi;
if [ "${VERSION_LINE}" = "${EVIDENCE_VERSION}" ]; then
  ASSERT=1;
  explain "this is the systemd build used for the article's evidence, so every assertion-bearing";
  explain "check below is asserted. The manual-page fixture and section 6 stay informational.";
elif [ "${VERSION}" -eq 255 ]; then
  ASSERT=0;
  explain "systemd 255, but not the build the article used (${EVIDENCE_VERSION}). A different";
  explain "255 build can differ, so systemd results here are recorded, not asserted. Only this";
  explain "harness's own invariants are asserted: the gate's usage error, its refusal when the";
  explain "control signature breaks, and its refusal on a release before 250.";
else
  ASSERT=0;
  explain "systemd ${VERSION}: the article's results come from 255. Every verifier result and";
  explain "manager property this harness checks is recorded as an observation here, matching";
  explain "or not. Only this";
  explain "harness's own invariants are asserted: the gate's usage error, its refusal when the";
  explain "control signature breaks, and its refusal on a release before 250.";
fi;
if [ "${MODE}" = self-test ]; then
  # The stub reports success on every release, so every check must apply here
  # whatever this host runs; otherwise the negative control proves nothing.
  ASSERT=1;
  explain "SELF-TEST: systemd-analyze verify is now a stub that exits 0 for every unit.";
  explain "Every assertion-bearing check is forced into assertion mode here, on any";
  explain "supported release.";
  explain "A correct run of this mode ends with failures, and the script reports that as a pass.";
fi;

banner "1. Default exit status: what a plain 'systemd-analyze verify' reports";
explain "What this tests: eleven small service units, each carrying one thing under test,";
explain "checked with no options. The exit status is what a CI gate usually reads.";
explain "Fixtures are in ${RUN_DIRECTORY}/fixtures. Each is a minimal unit; for example typo-value:";
fixture() {
  printf '[Unit]\nDescription=fixture\n%s[Service]\nExecStart=/bin/sleep 1\n%s' "${2}" "${3}" > "${RUN_DIRECTORY}/fixtures/${1}.service" || die "cannot create fixture ${1}.service";
};
fixture typo-name       ''                                      $'RestartSecc=5\n';
fixture typo-value      ''                                      $'Restart=on-failuer\n';
fixture wrong-section   $'Restart=always\n'                     '';
fixture duplicate       ''                                      $'Restart=always\nRestart=no\n';
fixture absent-workdir  ''                                      "WorkingDirectory=${ABSENT_DIRECTORY}"$'\n';
fixture x-prefix        ''                                      $'X-Restart=always\n';
fixture absent-manpage  $'Documentation=man:nosuchfile(1)\n'    '';
fixture absent-dep      "Requires=${MISSING_DEPENDENCY}"$'\n'        '';
fixture clean           ''                                      '';
printf '[Unit]\nDescription=fixture\n[Service]\nExecStart=%s\n' "${ABSENT_BINARY}" > "${RUN_DIRECTORY}/fixtures/absent-exec.service" || die "cannot create absent-exec.service";
printf '[Unit]\nDescription=fixture\n[Service]\nType=oneshot\nExecStart=/bin/sleep 1\nRestart=always\n' > "${RUN_DIRECTORY}/fixtures/oneshot-restart.service" || die "cannot create oneshot-restart.service";
sed 's/^/      | /' "${RUN_DIRECTORY}/fixtures/typo-value.service";
cd "${RUN_DIRECTORY}/fixtures" || exit 2;
UNITS=(typo-name typo-value wrong-section absent-exec absent-dep oneshot-restart duplicate absent-workdir x-prefix absent-manpage clean);
declare -A WHAT=(
  [typo-name]="misspelled directive name, RestartSecc="
  [typo-value]="real directive, unparseable value, Restart=on-failuer"
  [wrong-section]="valid directive in the wrong section, Restart= in [Unit]"
  [absent-exec]="ExecStart= points at a binary that does not exist"
  [absent-dep]="Requires= names a run-specific unit this harness never creates"
  [oneshot-restart]="Type=oneshot combined with Restart=always"
  [duplicate]="Restart=always, then Restart=no, same section"
  [absent-workdir]="WorkingDirectory= points at a directory that does not exist"
  [x-prefix]="X-Restart=always, the documented extension prefix"
  [absent-manpage]="Documentation= names a man page that does not exist"
  [clean]="nothing under test"
);
declare -A DEFAULT_EXIT_STATUS;
declare -A DEFAULT_EXPECT=([typo-name]=0 [typo-value]=0 [wrong-section]=0 [absent-exec]=1 [absent-dep]=1 [oneshot-restart]=1 [duplicate]=0 [absent-workdir]=0 [x-prefix]=0 [clean]=0);
explain "Command for each: systemd-analyze verify ./<fixture>.service";
explain "No --man= is passed, so the host's default policy applies, which section 6 examines.";
passed=0;
for unit in "${UNITS[@]}"; do
  explain "  ${unit}: ${WHAT[${unit}]}";
  verify "default_${unit}" "./${unit}.service";
  exit_status="${VERIFY_EXIT_STATUS}";
  DEFAULT_EXIT_STATUS["${unit}"]="${exit_status}";
  if [ "${unit}" = absent-exec ] && [ "${exit_status}" -eq 0 ]; then
    selftest_marker "a hard failure reported success";
  fi;
  if [ "${unit}" = absent-manpage ]; then
    echo "    info      exit ${exit_status}; depends on this host's man, see section 6";
  else
    expect "default exit, ${unit}" "${DEFAULT_EXPECT[${unit}]}" "${exit_status}";
  fi;
  if [ "${exit_status}" -eq 0 ]; then passed=$((passed + 1)); fi;
done;
failed_list="";
for unit in "${UNITS[@]}"; do
  if [ "${DEFAULT_EXIT_STATUS[${unit}]}" -ne 0 ]; then failed_list="${failed_list} ${unit}"; fi;
done;
explain "What it shows: ${passed} of 11 units exit 0 here. The ones that fail:${failed_list:- none}.";
explain "On the article's release, a misspelled name, a bad value, and a misplaced line all";
explain "exit 0, even though each changes what the unit does.";

banner "2. Where the diagnostic goes, and what it says";
explain "What this tests: whether the warning exists at all, and on which stream.";
explain "Command: systemd-analyze verify ./typo-name.service, stdout and stderr captured apart.";
verify stream_typo-name ./typo-name.service;
base="${RUN_DIRECTORY}/raw/stream_typo-name";
[ -r "${base}.stderr" ] || die "cannot read the captured stderr for typo-name";
[ -r "${base}.stdout" ] || die "cannot read the captured stdout for typo-name";
explain "  stderr: $(cat "${base}.stderr")";
explain "  stdout: $(wc -c < "${base}.stdout") bytes";
if [ ! -s "${base}.stderr" ]; then
  selftest_marker "the diagnostic vanished";
fi;
expect "stdout bytes for a warning" "0" "$(wc -c < "${base}.stdout" | tr -d ' ')";
expect "stderr names the misspelled key" "yes" "$(grep -q "Unknown key name 'RestartSecc'" "${base}.stderr" && echo yes || echo no)";
for pair in "typo-value|Failed to parse service restart specifier" "wrong-section|Unknown key name 'Restart' in section 'Unit'" "oneshot-restart|isn't allowed for Type=oneshot"; do
  unit="${pair%%|*}";
  want="${pair#*|}";
  verify "diagnostic_${unit}" "./${unit}.service";
  base="${RUN_DIRECTORY}/raw/diagnostic_${unit}";
  [ -r "${base}.stderr" ] || die "cannot read the captured stderr for ${unit}";
  explain "  ${unit} stderr: $(head -1 "${base}.stderr")";
  expect "diagnostic text, ${unit}" "yes" "$(grep -qF "${want}" "${base}.stderr" && echo yes || echo no)";
done;
explain "What it shows: in the three warning fixtures systemd reports the problem, says";
explain "'ignoring', writes it to stderr, and leaves the exit status at 0, so a gate reading";
explain "only the status never sees it. The oneshot fixture is here for contrast: its";
explain "diagnostic says 'Refusing' and its exit status is 1.";

banner "3. Counting warnings: --recursive-errors=no, one, and yes";
explain "What this tests: whether asking systemd to count warnings changes the verdict.";
explain "The option exists from systemd 250. Its three modes set which units' warnings count:";
explain "  no = the specified unit, one = it plus immediate dependencies, yes = it plus its";
explain "  associated dependencies.";
explain "Command for each: systemd-analyze verify --recursive-errors=<mode> ./<fixture>.service";
explain "Columns below: exit status under no, one, yes.";
declare -A MODE_EXPECT=([typo-name]="1 1 1" [typo-value]="1 1 1" [wrong-section]="1 1 1" [absent-exec]="1 1 1" [absent-dep]="0 1 1" [oneshot-restart]="1 1 1" [duplicate]="0 0 0" [absent-workdir]="0 0 0" [x-prefix]="0 0 0" [clean]="0 0 0");
for unit in "${UNITS[@]}"; do
  row="";
  for mode in no one yes; do
    verify "mode-${mode}_${unit}" --recursive-errors="${mode}" "./${unit}.service";
    row="${row} ${VERIFY_EXIT_STATUS}";
  done;
  row="${row# }";
  if [ "${unit}" = typo-value ] && [ "${row}" = "0 0 0" ]; then
    selftest_marker "warning promotion vanished";
  fi;
  if [ "${unit}" = absent-manpage ]; then
    echo "    info      absent-manpage: ${row} (host-dependent, see section 6)";
  else
    expect "no/one/yes, ${unit}" "${MODE_EXPECT[${unit}]}" "${row}";
  fi;
done;
explain "What it shows (asserted on 255): every explicit mode fails the three warning cases,";
explain "and the X- extension still passes, so the status now tells an intended extension";
explain "from an accident. Two catches: 'no' lets the missing dependency pass, and the";
explain "silent cases (duplicate, missing working directory) pass under every mode.";

banner "4. Which units a verdict covers";
explain "What this tests: a parent unit that references another unit, and whether a problem";
explain "in the referenced unit's file reaches the parent's exit status.";
explain "Columns below: exit status under default, no, one, yes.";
fixture ref-parent      $'Wants=typo-value.service\n'     '';
fixture ref-exec-parent $'Requires=absent-exec.service\n' '';
MODES_ROW=;
modes_row() {
  local tag="${1}" row_statuses recursive_mode; shift;
  verify "reference-default_${tag}" "${@}";
  row_statuses="${VERIFY_EXIT_STATUS}";
  for recursive_mode in no one yes; do
    verify "reference-${recursive_mode}_${tag}" --recursive-errors="${recursive_mode}" "${@}";
    row_statuses="${row_statuses} ${VERIFY_EXIT_STATUS}";
  done;
  MODES_ROW="${row_statuses}";
};
explain "  parent Wants= a unit whose file has the value typo:";
modes_row parent ./ref-parent.service;
expect "typo in referenced file" "0 0 0 1" "${MODES_ROW}";
explain "  same, with the referenced unit also named on the command line:";
modes_row parent-named ./ref-parent.service ./typo-value.service;
expect "typo, referenced unit named" "0 1 1 1" "${MODES_ROW}";
explain "  parent Requires= a unit whose ExecStart= binary is missing:";
modes_row exec ./ref-exec-parent.service;
expect "missing binary in referenced unit" "0 0 0 0" "${MODES_ROW}";
explain "  same, with the referenced unit also named:";
modes_row exec-named ./ref-exec-parent.service ./absent-exec.service;
expect "missing binary, referenced unit named" "1 1 1 1" "${MODES_ROW}";
explain "  seven relationship directives, the typo one hop and two hops away:";
# Each relationship directory holds its own typo-value.service, so the
# reference resolves from the directory of the unit being verified.
for relationship in Wants Requires Requisite BindsTo PartOf Upholds After; do
  mkdir "${RUN_DIRECTORY}/fixtures/${relationship}" || die "cannot create fixture directory ${relationship}";
  cp "${RUN_DIRECTORY}/fixtures/typo-value.service" "${RUN_DIRECTORY}/fixtures/${relationship}/" || die "cannot copy typo-value.service into ${relationship}";
  printf '[Unit]\nDescription=mid\n%s=typo-value.service\n[Service]\nExecStart=/bin/sleep 1\n' "${relationship}" > "${RUN_DIRECTORY}/fixtures/${relationship}/mid.service" || die "cannot create ${relationship}/mid.service";
  printf '[Unit]\nDescription=top\n%s=mid.service\n[Service]\nExecStart=/bin/sleep 1\n' "${relationship}" > "${RUN_DIRECTORY}/fixtures/${relationship}/top.service" || die "cannot create ${relationship}/top.service";
  modes_row "${relationship}-1" "./${relationship}/mid.service";
  expect "${relationship}, one hop" "0 0 0 1" "${MODES_ROW}";
  modes_row "${relationship}-2" "./${relationship}/top.service";
  expect "${relationship}, two hops" "0 0 0 1" "${MODES_ROW}";
done;
explain "What it shows: a warning inside a unit that is only referenced counts only under 'yes',";
explain "although the man page describes 'one' as covering immediate dependencies. A missing";
explain "binary in a referenced unit is never checked unless that unit is named. In the";
explain "systemd 255 source, 'one' compares recorded warning unit names with the command-line file names";
explain "only; other releases may differ. The practical rule: name every unit file";
explain "you own on the command line, then pick the mode for the units you only reference.";

if command -v sha256sum > /dev/null 2>&1 && command -v find > /dev/null 2>&1 && command -v sort > /dev/null 2>&1; then
  ( cd "${RUN_DIRECTORY}/fixtures" && find . -type f -name '*.service' -exec sha256sum {} + | sort ) > "${RUN_DIRECTORY}/fixture-sha256.txt" || die "cannot write the fixture checksum manifest";
  explain "Checksums of every .service file under fixtures/: ${RUN_DIRECTORY}/fixture-sha256.txt";
  explain "The gate controls and any user units below are outside that manifest.";
else
  explain "No checksum manifest: this host lacks sha256sum, find, or sort.";
fi;

banner "5. The article's gate, verbatim, and its self-test";
explain "What this tests: the minimal CI gate from the article, copied byte for byte, run";
explain "against all eleven units, then deliberately broken five ways to prove it refuses.";
explain "Its control is typo-value: it must exit 0 by default and nonzero with warnings";
explain "counted. If that signature breaks, the gate stops before checking anything (exit 2).";
cat > "${RUN_DIRECTORY}/gate/gate.sh" <<'GATE'
#!/usr/bin/env bash
# Minimal gate: systemd 250 or newer, one verify call per named unit file.
# The control lives beside this script in controls/typo-value.service.
set -uo pipefail;
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)";
control="${script_directory}/controls/typo-value.service";
if [ "${#}" -eq 0 ]; then
  printf 'usage: %s UNIT_FILE...\n' "${0}" >&2;
  exit 2;
fi;
version="$(systemd-analyze --version | awk 'NR == 1 { print $2 }')";
case "${version}" in
  ''|*[!0-9]*)
    printf 'ERROR: cannot read systemd version (%s)\n' "${version}" >&2;
    exit 2;;
esac;
if [ "${version}" -lt 250 ]; then
  printf 'ERROR: systemd %s predates --recursive-errors=\n' "${version}" >&2;
  exit 2;
fi;
systemd-analyze verify --man=no "${control}" >/dev/null 2>&1;
default_exit_status=${?};
systemd-analyze verify --man=no --recursive-errors=yes "${control}" >/dev/null 2>&1;
strict_exit_status=${?};
if [ "${default_exit_status}" -ne 0 ] || [ "${strict_exit_status}" -eq 0 ]; then
  printf 'ERROR: control %s gave default=%d strict=%d, expected 0 and nonzero\n' "${control}" "${default_exit_status}" "${strict_exit_status}" >&2;
  exit 2;
fi;
status=0;
for unit in "${@}"; do
  output="$(systemd-analyze verify --man=no --recursive-errors=yes -- "${unit}" 2>&1)";
  exit_status=${?};
  if [ "${exit_status}" -ne 0 ]; then
    printf 'FAIL %s (exit %d)\n' "${unit}" "${exit_status}";
    printf '%s\n' "${output}" | sed 's/^/     /';
    status=1;
  else
    printf 'PASS %s\n' "${unit}";
  fi;
done;
exit "${status}";
GATE
cp "${RUN_DIRECTORY}/fixtures/typo-value.service" "${RUN_DIRECTORY}/gate/controls/typo-value.service" || die "cannot install the gate control";
GATE_UNITS=();
for unit in "${UNITS[@]}"; do
  GATE_UNITS+=("./${unit}.service");
done;
explain "Command: bash ${RUN_DIRECTORY}/gate/gate.sh ./typo-name.service ... ./clean.service";
bash "${RUN_DIRECTORY}/gate/gate.sh" "${GATE_UNITS[@]}" > "${RUN_DIRECTORY}/gate/eleven_units.out" 2>&1;
gate_exit_status=${?};
grep -E '^(PASS|FAIL)' "${RUN_DIRECTORY}/gate/eleven_units.out" | sed 's/^/      | /';
if [ "${gate_exit_status}" -eq 2 ]; then
  selftest_marker "the gate refused to run on a broken control signature";
fi;
expect "gate exit, eleven units" "1" "${gate_exit_status}";
# absent-manpage is left out of the count: its verdict depends on this host's man
# (a stub passes it, a missing man fails it), which section 6 reports.
expect "units the gate passed, absent-manpage aside" "4" "$(grep '^PASS' "${RUN_DIRECTORY}/gate/eleven_units.out" | grep -vc absent-manpage)";
explain "    absent-manpage verdict on this host: $(awk '/absent-manpage/ { print $1; exit }' "${RUN_DIRECTORY}/gate/eleven_units.out")";
# Unlike verify(), this helper never calls die() and deliberately prints one
# status for command substitution.
gate_exit_status_for() { bash "${RUN_DIRECTORY}/gate/gate.sh" "${@}" > /dev/null 2>&1; echo "${?}"; };
explain "  a clean unit on its own (should pass, 0):";
expect "gate exit, clean unit" "0" "$(gate_exit_status_for ./clean.service)";
explain "  from another working directory (the control path is anchored to the script):";
expect "gate exit, another directory" "0" "$(cd / && gate_exit_status_for "${RUN_DIRECTORY}/fixtures/clean.service")";
explain "  a clean unit whose file name begins with a dash (read as a file, not an option, 0):";
cp "${RUN_DIRECTORY}/fixtures/clean.service" "${RUN_DIRECTORY}/gate/-leading-dash.service" || die "cannot create the leading-dash unit";
expect "gate exit, leading-dash file name" "0" "$(cd "${RUN_DIRECTORY}/gate" && gate_exit_status_for -leading-dash.service)";
explain "  sabotage 1, no arguments (usage error, 2):";
expect "gate exit, no arguments" "2" "$(gate_exit_status_for)" always;
explain "  sabotage 2, control replaced by a clean unit (signature broken, 2):";
cp "${RUN_DIRECTORY}/fixtures/clean.service" "${RUN_DIRECTORY}/gate/controls/typo-value.service" || die "cannot install the clean control";
expect "gate exit, clean control" "2" "$(gate_exit_status_for ./clean.service)" always;
explain "  sabotage 3, control file missing (2):";
mv "${RUN_DIRECTORY}/gate/controls/typo-value.service" "${RUN_DIRECTORY}/gate/sabotage-clean-control.service" || die "cannot move the control aside";
expect "gate exit, missing control" "2" "$(gate_exit_status_for ./clean.service)" always;
explain "  sabotage 4, control replaced by a hard failure (fails both ways, 2):";
cp "${RUN_DIRECTORY}/fixtures/absent-exec.service" "${RUN_DIRECTORY}/gate/controls/typo-value.service" || die "cannot install the hard-failure control";
expect "gate exit, hard-failure control" "2" "$(gate_exit_status_for ./clean.service)" always;
cp "${RUN_DIRECTORY}/fixtures/typo-value.service" "${RUN_DIRECTORY}/gate/controls/typo-value.service" || die "cannot restore the defective gate control";
explain "  sabotage 5, a systemd-analyze reporting release 249 (predates the option, 2):";
mkdir -p "${RUN_DIRECTORY}/stub-249" || die "cannot create the 249 stub directory";
cat > "${RUN_DIRECTORY}/stub-249/systemd-analyze" <<STUB || die "cannot write the 249 stub"
#!/bin/sh
if [ "\${1}" = --version ]; then echo "systemd 249 (249.11)"; exit 0; fi
exec "${REAL_ANALYZE}" "\${@}"
STUB
chmod +x "${RUN_DIRECTORY}/stub-249/systemd-analyze" || die "cannot make the 249 stub executable";
if "${RUN_DIRECTORY}/stub-249/systemd-analyze" --version > /dev/null 2>&1; then
  expect "gate exit, systemd 249" "2" "$(PATH="${RUN_DIRECTORY}/stub-249:${PATH}" gate_exit_status_for ./clean.service)" always;
else
  skip "gate exit, systemd 249: /tmp does not allow executing the stub (noexec mount)";
fi;
explain "What it shows: the gate fails the three warning cases and the three hard failures,";
explain "passes the rest, and refuses to run at all when its own control stops behaving.";
explain "PASS from this gate means only that verify exited 0, not that a unit is correct.";

banner "6. The Documentation= check depends on this host's man";
explain "What this tests: systemd-analyze checks Documentation=man: entries by running man.";
explain "If man is a stub that always succeeds, that check cannot fail. Not asserted.";
if command -v man > /dev/null 2>&1; then
  explain "  man:                 $(command -v man)";
  explain "  man nosuchfile exit: $(man nosuchfile > /dev/null 2>&1; echo ${?})";
  if command -v dpkg-divert > /dev/null 2>&1; then
    explain "  man diversion:       $(dpkg-divert --list /usr/bin/man 2> /dev/null || echo none)";
  fi;
else
  explain "  man: not installed";
fi;
verify manpage-yes --man=yes ./absent-manpage.service;
explain "  absent-manpage, --man=yes: exit ${VERIFY_EXIT_STATUS}";
verify manpage-no --man=no ./absent-manpage.service;
explain "  absent-manpage, --man=no:  exit ${VERIFY_EXIT_STATUS}";
explain "What it shows: whatever this host's man does decides that row. The article reports";
explain "it as inconclusive because its drafting image had a stub that exits 0 for any page.";

banner "7. Reading the value back from a running manager (your user manager, no root)";
explain "What this tests: what the manager actually holds for the value-typo unit, which";
explain "verification cannot tell you. A positive control spelled correctly must read back";
explain "Restart=on-failure first, so a Restart=no on the typo unit means something.";
if [ "${MODE}" = self-test ]; then
  RUNTIME_STATUS=skipped-self-test;
  skip "section 7 in self-test mode (the stub affects verify only)";
elif ! command -v systemctl > /dev/null 2>&1 || ! command -v sleep > /dev/null 2>&1; then
  RUNTIME_STATUS=no-systemctl;
  skip "section 7: this host has no systemctl or no sleep, which only this section needs";
elif [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-/nonexistent}" ] || ! systemctl --user show-environment > /dev/null 2>&1; then
  RUNTIME_STATUS=no-user-manager;
  skip "section 7: no user manager reachable (needs systemd as PID 1 and a login session; pid 1 is ${PID1})";
elif ! UNIT_PATH="$(systemctl --user show -p UnitPath --value)"; then
  die "the user manager answered show-environment but not a UnitPath query";
# systemctl printed UnitPath as a space-separated list on the tested release.
elif ! printf '%s\n' "${UNIT_PATH}" | tr ' ' '\n' | grep -qxF "${XDG_RUNTIME_DIR}/systemd/user"; then
  explain "  manager UnitPath: ${UNIT_PATH}";
  RUNTIME_STATUS=directory-not-searched;
  skip "section 7: the user manager does not search ${XDG_RUNTIME_DIR}/systemd/user";
else
  USER_UNIT_DIRECTORY="${XDG_RUNTIME_DIR}/systemd/user";
  explain "  manager UnitPath: ${UNIT_PATH}";
  explain "  the manager reports this directory in its UnitPath, so units placed there load";
  mkdir -p -- "${USER_UNIT_DIRECTORY}" || die "cannot create ${USER_UNIT_DIRECTORY}";
  explain "  user unit directory (runtime, cleared at logout or reboot): ${USER_UNIT_DIRECTORY}";
  RUN_IDENTIFIER="${RUN_DIRECTORY##*.}";
  POSITIVE_CONTROL_UNIT="revisualized-ignored-directive-${RUN_IDENTIFIER}-restart-positive.service";
  VALUE_TYPO_UNIT="revisualized-ignored-directive-${RUN_IDENTIFIER}-typo-value.service";
  ABSENT_WORKING_DIRECTORY_UNIT="revisualized-ignored-directive-${RUN_IDENTIFIER}-absent-workdir.service";
  collision=0;
  for unit in "${POSITIVE_CONTROL_UNIT}" "${VALUE_TYPO_UNIT}" "${ABSENT_WORKING_DIRECTORY_UNIT}"; do
    if [ -e "${USER_UNIT_DIRECTORY}/${unit}" ] || [ -L "${USER_UNIT_DIRECTORY}/${unit}" ]; then
      echo "ERROR: refusing to overwrite an existing user unit: ${USER_UNIT_DIRECTORY}/${unit}" >&2;
      collision=1;
    fi;
  done;
  if [ "${collision}" -ne 0 ]; then
    exit 2;
  fi;
  # Registered before the writes, so cleanup covers a file that was created and
  # then failed partway. Setup failure here is an error, not a skip.
  USER_UNITS=("${POSITIVE_CONTROL_UNIT}" "${VALUE_TYPO_UNIT}" "${ABSENT_WORKING_DIRECTORY_UNIT}");
  printf '[Unit]\nDescription=positive control\n[Service]\nExecStart=/bin/sleep 1\nRestart=on-failure\n' > "${USER_UNIT_DIRECTORY}/${POSITIVE_CONTROL_UNIT}" || die "cannot create ${POSITIVE_CONTROL_UNIT}";
  cp "${RUN_DIRECTORY}/fixtures/typo-value.service" "${USER_UNIT_DIRECTORY}/${VALUE_TYPO_UNIT}" || die "cannot create ${VALUE_TYPO_UNIT}";
  cp "${RUN_DIRECTORY}/fixtures/absent-workdir.service" "${USER_UNIT_DIRECTORY}/${ABSENT_WORKING_DIRECTORY_UNIT}" || die "cannot create ${ABSENT_WORKING_DIRECTORY_UNIT}";
  systemctl --user daemon-reload || die "systemctl --user daemon-reload failed";
  load_state="$(systemctl --user show -p LoadState --value "${POSITIVE_CONTROL_UNIT}")" || die "cannot read LoadState from ${POSITIVE_CONTROL_UNIT}";
  if [ "${load_state}" != loaded ]; then
    RUNTIME_STATUS=units-not-loaded;
    skip "section 7: the user manager did not load units from ${USER_UNIT_DIRECTORY} (LoadState=${load_state})";
  else
    explain "Command: systemctl --user show -p Restart <unit>";
    positive_control_restart="$(systemctl --user show -p Restart "${POSITIVE_CONTROL_UNIT}")" || die "cannot read Restart from ${POSITIVE_CONTROL_UNIT}";
    value_typo_restart="$(systemctl --user show -p Restart "${VALUE_TYPO_UNIT}")" || die "cannot read Restart from ${VALUE_TYPO_UNIT}";
    explain "  positive control (${POSITIVE_CONTROL_UNIT}): ${positive_control_restart}";
    explain "  value typo       (${VALUE_TYPO_UNIT}): ${value_typo_restart}";
    expect "read-back, positive control" "Restart=on-failure" "${positive_control_restart}";
    expect "read-back, value typo" "Restart=no" "${value_typo_restart}";
    explain "Command: systemctl --user start ${ABSENT_WORKING_DIRECTORY_UNIT}";
    systemctl --user start "${ABSENT_WORKING_DIRECTORY_UNIT}" > "${RUN_DIRECTORY}/raw/working_directory_start.txt" 2>&1;
    working_directory_start_status=${?};
    # Type=simple reports a successful start as soon as the process is forked,
    # so the exec failure can land after the start command returns. Wait for the
    # unit to settle before reading its properties.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      working_directory_active_state="$(systemctl --user show -p ActiveState --value "${ABSENT_WORKING_DIRECTORY_UNIT}")" || die "cannot read ActiveState from ${ABSENT_WORKING_DIRECTORY_UNIT}";
      case "${working_directory_active_state}" in
        activating|active|reloading)
          sleep 0.5;;
        *)
          break;;
      esac;
    done;
    case "${working_directory_active_state}" in
      activating|active|reloading)
        die "${ABSENT_WORKING_DIRECTORY_UNIT} stayed in state ${working_directory_active_state} through the polling window";;
    esac;
    systemctl --user show -p LoadState -p ActiveState -p SubState -p Result -p ExecMainCode -p ExecMainStatus "${ABSENT_WORKING_DIRECTORY_UNIT}" > "${RUN_DIRECTORY}/raw/working_directory_properties.txt" || die "cannot read properties from ${ABSENT_WORKING_DIRECTORY_UNIT}";
    sed 's/^/    /' "${RUN_DIRECTORY}/raw/working_directory_properties.txt";
    working_directory_exit_status="$(systemctl --user show -p ExecMainStatus --value "${ABSENT_WORKING_DIRECTORY_UNIT}")" || die "cannot read ExecMainStatus from ${ABSENT_WORKING_DIRECTORY_UNIT}";
    working_directory_result="$(systemctl --user show -p Result --value "${ABSENT_WORKING_DIRECTORY_UNIT}")" || die "cannot read Result from ${ABSENT_WORKING_DIRECTORY_UNIT}";
    explain "  start exit status: ${working_directory_start_status}; Result=${working_directory_result}; ExecMainStatus=${working_directory_exit_status} (systemd.exec(5): 200 is EXIT_CHDIR)";
    explain "  the client status is recorded, not asserted: the verdict comes from the settled properties";
    expect "missing WorkingDirectory= unit ends in failure" "failed" "${working_directory_active_state}";
    expect "failure result" "exit-code" "${working_directory_result}";
    expect "failure status is EXIT_CHDIR" "200" "${working_directory_exit_status}";
    RUNTIME_STATUS=executed;
    explain "What it shows: the manager holds Restart=no for a unit whose file asked for a";
    explain "restart policy, and the missing directory is only discovered at start time.";
  fi;
fi;

if [ "${REQUIRE_RUNTIME}" -eq 1 ] && [ "${RUNTIME_STATUS}" != executed ]; then
  FAILURES=$((FAILURES + 1));
  echo "    FAIL      --require-runtime was given and the runtime section is ${RUNTIME_STATUS}";
  record FAIL "--require-runtime: runtime section ${RUNTIME_STATUS}";
fi;

banner "RESULT";
if [ "${MODE}" = self-test ]; then
  explain "systemd ${VERSION}; assertion mode: self-test, every assertion-bearing check forced on";
  explain "assertion mismatches under the stub: ${FAILURES}   assertions still matching: ${OK}   skipped: ${SKIPS}";
  explain "a high mismatch count is the point of this mode";
else
  explain "systemd ${VERSION}; assertion mode: $([ "${ASSERT}" -eq 1 ] && echo 'all results (the article release)' || echo 'harness invariants asserted, systemd results observed')";
  explain "ok: ${OK}   fail: ${FAILURES}   observed, not asserted: ${OBSERVED} (matching the article: ${OBSERVED_MATCHING}, differing: ${OBSERVED_DIFFERING})   skipped: ${SKIPS}";
  if [ "${OBSERVED_DIFFERING}" -gt 0 ]; then
    explain "differing observations: grep 'article \[' ${RUN_DIRECTORY}/summary.txt";
  fi;
fi;
explain "runtime section: ${RUNTIME_STATUS}";
if [ "${PATHS_LOCAL}" = yes ]; then
  explain "absent paths: run-local, because this host has /opt/definitely-absent or /opt/absent/app";
fi;
explain "evidence:  ${RUN_DIRECTORY}";
if [ "${CLEAN}" -eq 1 ]; then
  explain "cleanup:   --clean was given; the run directory is removed on exit";
else
  explain "cleanup:   rm -rf -- ${RUN_DIRECTORY}   (or: bash ${0} --purge)";
fi;
if [ "${MODE}" = self-test ]; then
  explain "targeted catches: ${SELFTEST_MARKERS} of 4; assertion mismatches under the stub: ${FAILURES}";
  if [ "${SELFTEST_MARKERS}" -eq 4 ]; then
    echo "SELF-TEST: PASS (all four targeted checks caught the always-success verifier: the hard failure, warning promotion, the diagnostic, and the gate's control)";
    exit 0;
  fi;
  echo "SELF-TEST: FAIL (only ${SELFTEST_MARKERS} of 4 targeted checks caught the always-success verifier; see ${RUN_DIRECTORY}/summary.txt)";
  exit 1;
fi;
if [ "${FAILURES}" -eq 0 ] && [ "${ASSERT}" -ne 1 ] && [ "${SKIPS}" -eq 0 ]; then
  echo "DEMONSTRATIONS: OBSERVED (the harness ran and its own invariants held; systemd results on this release were recorded, not asserted: ${OBSERVED_MATCHING} match the article, ${OBSERVED_DIFFERING} differ, ${SKIPS} skipped)";
  exit 0;
fi;
if [ "${FAILURES}" -eq 0 ] && [ "${SKIPS}" -eq 0 ]; then
  echo "DEMONSTRATIONS: PASS (every check ran and behaved as the article describes on this release; this says nothing about whether any unit you deploy is correct)";
  exit 0;
fi;
if [ "${FAILURES}" -eq 0 ]; then
  echo "DEMONSTRATIONS: PARTIAL (no check failed, ${SKIPS} skipped; exit status is still 0, pass --require-runtime to make a skip an error)";
  exit 0;
fi;
echo "DEMONSTRATIONS: FAIL (${FAILURES} checks differ from the article; see ${RUN_DIRECTORY}/summary.txt)";
exit 1;
