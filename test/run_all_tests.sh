#!/usr/bin/env bash
# Path:     test/run_all_tests.sh
# Project:  ignored-directive-reproductions
# Revision: 2
# Updated:  2026-09-26
# Purpose:  The single test entry point for this repository. CI runs exactly
#           this command, and so can you, from any directory:
#
#               bash test/run_all_tests.sh;
#
#           Exits 0 only when every suite below passed. Each suite reports
#           how many tests it executed, and a suite that executed none fails
#           the run, here and in CI alike. When TESTS_EXECUTED_FILE is set, as
#           CI sets it, each suite also appends "<label><TAB><count>" to that
#           file. Scratch output goes to one temporary directory, removed on
#           exit.
#
# Suites:
#           The reproduction script, which asserts its own checks.
#           Its --self-test negative control, which must catch a stub verifier.
#
# History:  Revision 1 counted recorded observations as executed tests.
#           On any systemd build but the article's they cannot fail, so
#           the count claimed more than the run checked. Revision 2
#           counts only asserted checks and prints observations apart.
set -euo pipefail;

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)";
cd "${project_root}";
work_directory="$(mktemp -d "${TMPDIR:-/tmp}/revisualized_tests.XXXXXX")";
trap 'rm -rf -- "${work_directory}"' EXIT;

fail() {
  echo "FAIL: ${1}" >&2;
  exit 1;
};

# Refuses a count of zero or a count that is not a number. A suite that ran
# nothing has not passed.
record_tests_executed() {
  local label="${1}";
  local count="${2}";
  if ! [[ "${count}" =~ ^[0-9]+$ ]] || [ "${count}" -eq 0 ]; then
    fail "suite '${label}' reported '${count}' tests executed";
  fi;
  echo "  executed: ${label}: ${count}";
  if [ -n "${TESTS_EXECUTED_FILE:-}" ]; then
    printf '%s\t%s\n' "${label}" "${count}" >> "${TESTS_EXECUTED_FILE}";
  fi;
};

# The reproduction script asserts its own checks and exits non-zero when one
# fails. On systemd 255.4-1ubuntu8.15, the article's build, every expectation
# is asserted. On any other build, systemd results are recorded as
# observations that cannot fail, and only the script's own invariants are
# asserted. Only asserted checks are counted as executed tests; observations
# are printed but not counted, because a check that cannot fail has not passed.
run_reproductions() {
  local log_file="${work_directory}/reproductions.log";
  local counts;
  local asserted_total;
  local observed_total;
  echo "== reproductions: bash ignored_directive_reproductions.sh --clean";
  bash ignored_directive_reproductions.sh --clean 2>&1 | tee "${log_file}";
  counts="$(sed -n -E 's/.*ok: ([0-9]+) +fail: ([0-9]+) +observed, not asserted: ([0-9]+).*/\1 \2 \3/p' "${log_file}" | tail -1)";
  [ -n "${counts}" ] || fail "the reproduction script printed no result counts";
  asserted_total="$(echo "${counts}" | awk '{ print $1 + $2; }')";
  observed_total="$(echo "${counts}" | awk '{ print $3; }')";
  echo "  recorded, not asserted, not counted: ${observed_total} systemd observations";
  record_tests_executed "reproduction checks asserted" "${asserted_total}";
};

# Negative control shipped with the script: systemd-analyze is replaced by a
# stub that always succeeds, and four targeted checks must catch it. The
# evidence directory is kept on failure and removed on success.
run_self_test() {
  local log_file="${work_directory}/self_test.log";
  local catches;
  local evidence_directory;
  echo "== self-test: bash ignored_directive_reproductions.sh --self-test";
  bash ignored_directive_reproductions.sh --self-test 2>&1 | tee "${log_file}";
  catches="$(sed -n -E 's/.*targeted catches: ([0-9]+) of 4.*/\1/p' "${log_file}" | tail -1)";
  [ "${catches:-0}" -eq 4 ] || fail "self-test caught ${catches:-0} of 4";
  evidence_directory="$(sed -n -E 's/^ *evidence: +(\/tmp\/revisualized_ignored_directive\.[A-Za-z0-9]+)$/\1/p' "${log_file}" | tail -1)";
  if [ -n "${evidence_directory}" ] && [ -f "${evidence_directory}/.ignored_directive_run" ]; then
    rm -rf -- "${evidence_directory}";
  fi;
  record_tests_executed "self-test targeted catches" "${catches}";
};

run_reproductions;
run_self_test;

echo "All suites passed.";
