#!/bin/sh
# phase8-budget.sh — enforce the Phase 8 loop budget of /umo-jira-tracker:mr.
#
# Why this exists: Step 8a used to ask the agent to do this bookkeeping in its
# head (compare `date +%s` output, remember a running iteration/poll count
# across dozens of tool calls). Prose cannot enforce a budget; this can.
#
# Usage:
#   phase8-budget.sh poll      <key>   # every pipeline/discussion check
#   phase8-budget.sh iteration <key>   # BEFORE pushing a fix (the gate)
#   phase8-budget.sh status    <key>   # read-only, for the Step 8d/8e report
#                                      # also splits elapsed time into polling
#                                      # vs remediation — see POLL_GAP_SECONDS
#   phase8-budget.sh reset     <key>   # forget this MR's budget, start fresh
#
# <key> is "{project-id}-{iid}", both resolved by Phase 6 (e.g. 12345678-33).
#
# Exit codes:
#   0  within budget (or a successful `status` / `reset`)
#   1  BUDGET EXCEEDED — route to Step 8d, do not start another iteration
#   2  usage error (bad/missing subcommand or key) — the caller used this wrong,
#      which is NOT the same as an exhausted budget
#   3  environment broken: the state directory or its lock is unusable. Not a
#      usage mistake and not budget exhaustion — fall back to Step 8a's manual
#      `date +%s` bookkeeping, exactly as if this script could not be found.
#
# POSIX sh only. Externals used: date, mkdir, rm, cat, sleep. No bash-isms, no
# jq/python.
#
# State: ${TMPDIR:-/tmp}/umo-phase8/<key>.state — deliberately outside the git
# working tree so it can never be committed. Plain KEY=VALUE lines:
# start_time / iterations / polls enforce the budget; last_activity_at /
# poll_seconds / remediation_seconds only feed `status`, and a damaged or
# absent one of those never invalidates the file (see load_state).
#
# Parallel sessions: state is isolated per MR key, so concurrent Phase 8 runs
# on *different* MRs on the same machine never interfere. For the *same* key,
# every mutation (poll / iteration / reset) is serialized by an advisory
# mkdir-based lock at <key>.lock, so concurrent callers cannot lose an
# increment; `status` is read-only and takes no lock. A lock left behind by a
# killed process goes stale once its recorded timestamp is older than
# LOCK_STALE_SECONDS and is then cleared automatically, so a crash cannot
# deadlock future runs. Waiters never break a lock on any weaker evidence than
# that timestamp — see the LOCK_* constants below.

LC_ALL=C
export LC_ALL

# ---------------------------------------------------------------------------
# BUDGET CONSTANTS — keep in sync with Step 8a of
# plugins/umo-jira-tracker/commands/umo-jira-tracker:mr.md, which documents the
# same three numbers in prose and carries a matching comment pointing back at
# this file. Change one without the other and the documented budget stops
# matching the enforced one.
# ---------------------------------------------------------------------------
MAX_ITERATIONS=6
MAX_SECONDS=2700 # 45 minutes
MAX_POLLS=40

# ---------------------------------------------------------------------------
# TIME ATTRIBUTION — reporting only, enforces nothing.
#
# Why this exists: a real run reported "poll 10/40 | elapsed 1200s/2700s" and
# read as if polling were burning the clock. It wasn't — ~10 of those minutes
# were spent reading a failed job's log, checking a CVE, asking the developer a
# question and waiting for the answer, then pushing a fix. The poll counter
# stood still through all of it while the clock ran, so the two numbers side by
# side slander a loop that behaved correctly. Splitting elapsed time tells
# whoever reads the Step 8d handoff which half to actually go look at.
#
# A gap between two consecutive counted calls no longer than this is plausibly
# one of Step 8b/8c's own sleep intervals (a flat 180s, per Step 8b), so it
# counts as polling; a longer one is the agent off doing something else, and
# counts as remediation.
#
# Why 360 and not 540: the threshold is one sleep interval plus a full extra
# interval of slack for the cycle's own overhead — the GitLab call, this
# script, and the agent's model turn between them. That overhead is an
# absolute quantity; it does not grow just because the sleep got longer. So
# preserving the *ratio* from when the interval was 30-60s (3x, which would
# give 540) buys 360s of slack for overhead that has never plausibly exceeded
# a fraction of that, and pays for it by blinding the field to every
# remediation block under nine minutes — including the ~6min human wait and
# the ~10min CI investigation that motivated the split in the first place.
# Sizing the slack in absolute terms instead of scaling it with the interval
# keeps normal polling safely inside "polling" while leaving the smallest
# reported remediation block at six minutes.
#
# The error direction still favours calling a short remediation "polling":
# what must never happen is a normal poll cycle systematically landing in
# "remediation", which would empty the field of meaning.
# ---------------------------------------------------------------------------
POLL_GAP_SECONDS=360

# Advisory-lock tuning. Not a budget limb — just a low-contention safety net.
# A poll/iteration holds the lock for microseconds, so 10s is already generous
# and exhausting LOCK_MAX_TRIES whole-second retries can only be reached by a
# wedged filesystem.
LOCK_STALE_SECONDS=10
LOCK_MAX_TRIES=25
#
# A waiter reclaims a lock ONLY on the evidence of a valid, old `acquired_at`
# stamp. It must never decide that a lock with no readable stamp is orphaned:
# that cannot be distinguished from a live holder that simply has not been
# scheduled yet, and under real contention (dozens of forked sh/date/mkdir
# processes competing for CPU) a healthy holder can be slow. An earlier
# version guessed here with a consecutive-sighting threshold and, under load,
# evicted live holders — breaking mutual exclusion outright (three processes
# in the critical section at once, increments lost) and worse, leaving the
# evicted holder to later rm -rf a lock a *different* process had legitimately
# re-created. The only unhandled case is now a holder killed in the single
# statement between `mkdir` succeeding and its stamp write; waiters simply
# wait that lock out and exit 3 (manual-bookkeeping fallback) via
# LOCK_MAX_TRIES, which is a safe failure mode rather than a corrupting one.

usage() {
    printf '%s\n' "phase8-budget.sh: $1" >&2
    printf '%s\n' "usage: phase8-budget.sh {poll|iteration|status|reset} <key>" >&2
    printf '%s\n' "       <key> is {project-id}-{iid}, e.g. 12345678-33" >&2
    exit 2
}

# Drop anything outside [A-Za-z0-9._-] so the key can never escape the state
# directory or name something unexpected. Pure parameter expansion — no `tr`.
sanitize_key() {
    sk_in=$1
    sk_out=''
    while [ -n "$sk_in" ]; do
        sk_ch=${sk_in%"${sk_in#?}"} # first character of $sk_in
        sk_in=${sk_in#?}
        case $sk_ch in
        [A-Za-z0-9._-]) sk_out=$sk_out$sk_ch ;;
        *) ;;
        esac
    done
    printf '%s' "$sk_out"
}

is_uint() {
    case $1 in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
    esac
}

# The three enforcement fields stay first and keep their names, so a state
# file written here is still readable by a build of this script that predates
# the attribution fields (it ignores unknown keys).
write_state() {
    printf 'start_time=%s\niterations=%s\npolls=%s\nlast_activity_at=%s\npoll_seconds=%s\nremediation_seconds=%s\n' \
        "$ST_START" "$ST_ITER" "$ST_POLLS" \
        "$ST_LAST" "$ST_POLL_SECS" "$ST_REM_SECS" >"$STATE_FILE"
}

init_state() {
    ST_START=$(date +%s)
    ST_ITER=0
    ST_POLLS=0
    ST_LAST=$ST_START
    ST_POLL_SECS=0
    ST_REM_SECS=0
    write_state
}

# Exit 3, not 2: a broken environment is not a usage mistake. The caller's
# documented response is to fall back to manual `date +%s` bookkeeping.
env_broken() {
    printf '%s\n' "phase8-budget.sh: $1" >&2
    printf '%s\n' "phase8-budget.sh: state tracking unavailable — fall back to manual date +%s bookkeeping (Step 8a)" >&2
    exit 3
}

ensure_state_dir() {
    [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null
    [ -d "$STATE_DIR" ] || env_broken "cannot create state directory $STATE_DIR"
}

# --- Advisory lock (mkdir is atomic on POSIX filesystems; no flock needed,
# --- which matters because flock is absent on stock macOS and isn't POSIX).
LOCK_HELD=0

release_lock() {
    if [ "$LOCK_HELD" = 1 ]; then
        LOCK_HELD=0
        rm -rf "$LOCK_DIR"
    fi
}

acquire_lock() {
    al_tries=0
    while :; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            LOCK_HELD=1
            # Age marker for stale-lock recovery. Read back with `cat`, never
            # `stat` — stat's flags differ between BSD/macOS and GNU/Linux.
            # Braces around the redirect so a failure to *open* the file is
            # silenced too (`2>/dev/null` on `date` alone would not cover the
            # shell's own redirection error).
            { date +%s >"$LOCK_DIR/acquired_at"; } 2>/dev/null
            # Defence in depth: if the stamp is not there afterwards, this
            # lock is not really ours (nothing in the current design can do
            # that, but never rm -rf a directory we may not own). Give up
            # ownership without deleting anything and re-enter the queue.
            if [ -f "$LOCK_DIR/acquired_at" ]; then
                return 0
            fi
            LOCK_HELD=0
        else
            al_stamp=''
            if [ -f "$LOCK_DIR/acquired_at" ]; then
                al_stamp=$(cat "$LOCK_DIR/acquired_at" 2>/dev/null)
            fi
            # Reclaim ONLY on a valid, old stamp: unambiguous evidence the
            # holder is gone or wedged. A missing/unreadable stamp is treated
            # exactly like "someone holds it" — keep waiting, never clear it.
            # See the LOCK_* constants above for why.
            if is_uint "$al_stamp"; then
                al_age=$(($(date +%s) - al_stamp))
                if [ "$al_age" -gt "$LOCK_STALE_SECONDS" ] || [ "$al_age" -lt 0 ]; then
                    rm -rf "$LOCK_DIR"
                    continue
                fi
            fi
        fi
        al_tries=$((al_tries + 1))
        if [ "$al_tries" -ge "$LOCK_MAX_TRIES" ]; then
            env_broken "could not acquire $LOCK_DIR after ${LOCK_MAX_TRIES} attempts"
        fi
        sleep 1
    done
}

# Load state into ST_START / ST_ITER / ST_POLLS. Returns 1 when there is no
# usable state (missing file, or values that are not plain integers because
# something truncated or hand-edited it).
load_state() {
    ST_START=''
    ST_ITER=''
    ST_POLLS=''
    ST_LAST=''
    ST_POLL_SECS=''
    ST_REM_SECS=''
    [ -f "$STATE_FILE" ] || return 1
    # Redirecting the loop (not piping into it) keeps the assignments in this
    # shell in both dash and bash.
    while IFS='=' read -r ls_k ls_v; do
        case $ls_k in
        start_time) ST_START=$ls_v ;;
        iterations) ST_ITER=$ls_v ;;
        polls) ST_POLLS=$ls_v ;;
        last_activity_at) ST_LAST=$ls_v ;;
        poll_seconds) ST_POLL_SECS=$ls_v ;;
        remediation_seconds) ST_REM_SECS=$ls_v ;;
        *) ;;
        esac
    done <"$STATE_FILE"
    is_uint "$ST_START" || return 1
    is_uint "$ST_ITER" || return 1
    is_uint "$ST_POLLS" || return 1
    # The attribution fields are reporting-only, so a missing or damaged one
    # must never invalidate a state file whose enforcement counters are sound —
    # that would restart the wall clock and hand the loop 45 minutes it has
    # already spent. They are also absent from every state file written before
    # they existed. Default them instead of failing the load.
    if is_uint "$ST_LAST"; then
        is_uint "$ST_POLL_SECS" || ST_POLL_SECS=0
        is_uint "$ST_REM_SECS" || ST_REM_SECS=0
    else
        # With no usable marker the next gap is charged from start_time, i.e.
        # the whole run so far. Any accumulator that happened to survive would
        # then be counted a second time, letting polling+remediation exceed
        # elapsed and quietly breaking the identity `status` reports. Restart
        # the breakdown rather than mixing two incompatible baselines.
        ST_LAST=$ST_START
        ST_POLL_SECS=0
        ST_REM_SECS=0
    fi
    return 0
}

# Charge the time since the previous counted call to whichever accumulator the
# gap's length implicates, then re-stamp the marker. Called inside the lock on
# exactly the calls that increment a counter, so the breakdown can never drift
# from the counts it explains.
attribute_gap() {
    ag_now=$(date +%s)
    ag_gap=$((ag_now - ST_LAST))
    [ "$ag_gap" -ge 0 ] || ag_gap=0
    if [ "$ag_gap" -le "$POLL_GAP_SECONDS" ]; then
        ST_POLL_SECS=$((ST_POLL_SECS + ag_gap))
    else
        ST_REM_SECS=$((ST_REM_SECS + ag_gap))
    fi
    ST_LAST=$ag_now
}

# Sets ELAPSED, and EXCEEDED to a comma-separated list of blown limbs ('' if
# none). The iterations limb only trips above the cap: reaching exactly
# MAX_ITERATIONS is the last *allowed* fix, and the poll that verifies whether
# that fix worked must still be permitted. A 7th fix is refused by the
# `iteration` subcommand itself.
evaluate() {
    ELAPSED=$(($(date +%s) - ST_START))
    [ "$ELAPSED" -ge 0 ] || ELAPSED=0
    EXCEEDED=''
    if [ "$ST_POLLS" -gt "$MAX_POLLS" ]; then
        EXCEEDED=polls
    fi
    if [ "$ELAPSED" -ge "$MAX_SECONDS" ]; then
        if [ -n "$EXCEEDED" ]; then EXCEEDED="$EXCEEDED, wall-clock"; else EXCEEDED=wall-clock; fi
    fi
    if [ "$ST_ITER" -gt "$MAX_ITERATIONS" ]; then
        if [ -n "$EXCEEDED" ]; then EXCEEDED="$EXCEEDED, iterations"; else EXCEEDED=iterations; fi
    fi
}

verdict() {
    if [ -n "$EXCEEDED" ]; then
        printf 'BUDGET EXCEEDED: %s' "$EXCEEDED"
    else
        printf 'OK'
    fi
}

CMD=$1
RAW_KEY=$2

case $CMD in
-h | --help | help)
    printf '%s\n' "usage: phase8-budget.sh {poll|iteration|status|reset} <key>"
    printf '%s\n' "       <key> is {project-id}-{iid}, e.g. 12345678-33"
    printf '%s\n' "exit 0 = within budget, 1 = budget exceeded, 2 = usage error"
    exit 0
    ;;
'') usage "missing subcommand" ;;
poll | iteration | status | reset) ;;
*) usage "unknown subcommand '$CMD'" ;;
esac

[ -n "$RAW_KEY" ] || usage "missing <key> for '$CMD'"
KEY=$(sanitize_key "$RAW_KEY")
[ -n "$KEY" ] || usage "<key> '$RAW_KEY' has no usable [A-Za-z0-9._-] characters"

STATE_DIR="${TMPDIR:-/tmp}/umo-phase8"
STATE_FILE="$STATE_DIR/$KEY.state"
LOCK_DIR="$STATE_DIR/$KEY.lock"

# Release the lock on every exit path, including signals, so a critical
# section can never leak a held lock under normal operation.
trap release_lock EXIT
trap 'release_lock; exit 130' INT
trap 'release_lock; exit 143' TERM
trap 'release_lock; exit 129' HUP

case $CMD in
poll)
    ensure_state_dir
    acquire_lock
    load_state || init_state
    ST_POLLS=$((ST_POLLS + 1))
    attribute_gap
    write_state
    release_lock
    evaluate
    printf 'poll %s/%s | elapsed %ss/%ss | iterations %s/%s | %s\n' \
        "$ST_POLLS" "$MAX_POLLS" "$ELAPSED" "$MAX_SECONDS" \
        "$ST_ITER" "$MAX_ITERATIONS" "$(verdict)"
    [ -z "$EXCEEDED" ] || exit 1
    exit 0
    ;;
iteration)
    ensure_state_dir
    acquire_lock
    load_state || init_state
    evaluate
    # Refuse the fix push when the iteration cap is already reached or the
    # clock is already blown, and do NOT increment — the counter must never
    # overshoot MAX_ITERATIONS.
    if [ "$ST_ITER" -ge "$MAX_ITERATIONS" ]; then
        if [ -n "$EXCEEDED" ]; then EXCEEDED="$EXCEEDED, iterations"; else EXCEEDED=iterations; fi
    fi
    if [ -n "$EXCEEDED" ]; then
        release_lock
        printf 'iteration %s/%s | elapsed %ss/%ss | polls %s/%s | %s\n' \
            "$ST_ITER" "$MAX_ITERATIONS" "$ELAPSED" "$MAX_SECONDS" \
            "$ST_POLLS" "$MAX_POLLS" "$(verdict)"
        exit 1
    fi
    ST_ITER=$((ST_ITER + 1))
    attribute_gap
    write_state
    release_lock
    printf 'iteration %s/%s | elapsed %ss/%ss | polls %s/%s | OK\n' \
        "$ST_ITER" "$MAX_ITERATIONS" "$ELAPSED" "$MAX_SECONDS" \
        "$ST_POLLS" "$MAX_POLLS"
    exit 0
    ;;
status)
    # Read-only: never creates, increments, or repairs state. Always exits 0,
    # even when over budget — the caller decides what to do with the numbers.
    if load_state; then
        evaluate
        # Only counted calls attribute time, and `status` must not count, so
        # the stretch since the last poll/iteration is still unclassified.
        # Report it rather than leaving the three numbers refusing to add up.
        ST_UNATTR=$((ELAPSED - ST_POLL_SECS - ST_REM_SECS))
        [ "$ST_UNATTR" -ge 0 ] || ST_UNATTR=0
        printf 'status | poll %s/%s | elapsed %ss/%ss | polling %ss | remediation %ss | since-last %ss | iterations %s/%s | %s\n' \
            "$ST_POLLS" "$MAX_POLLS" "$ELAPSED" "$MAX_SECONDS" \
            "$ST_POLL_SECS" "$ST_REM_SECS" "$ST_UNATTR" \
            "$ST_ITER" "$MAX_ITERATIONS" "$(verdict)"
    else
        printf 'status | no budget state for %s (Phase 8 has not polled yet, or state was reset)\n' "$KEY"
    fi
    exit 0
    ;;
reset)
    # Locked like the other mutations: Step 8a calls reset at the start of
    # every Phase 8 run, and it must not tear state out from under a
    # concurrent poll/iteration mid-write.
    ensure_state_dir
    acquire_lock
    rm -f "$STATE_FILE"
    release_lock
    printf 'reset | budget state cleared for %s\n' "$KEY"
    exit 0
    ;;
esac
