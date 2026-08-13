#!/usr/bin/env python3
"""Read, validate and WRITE reviewer findings. The JSON boundary, in one place.

Reviewers used to return a prose block that something -- a hook scraping a transcript, or a
person reading the markdown and retyping it -- had to parse back into fields. Every defect in
that path came from the parsing. The fix is not a better parser. The reviewer returns data.

Python rather than shell because `python3` is already a hard dependency (validate.py runs in
CI), so the constraint that once justified hand-rolling JSON with awk and sed was never real
-- docs/LESSONS.md S7.

THIS MODULE ALSO WRITES, and that is a correction. The first version validated here and let
`kit-finding.sh` build the event line with printf, on the principle that one module decides and
another records. Both T3 reviewers found the same critical: that printf interpolated `lang`,
`pattern`, `domain` and `file` unescaped into an append-only COMMITTED log, and because the awk
reader takes the first match, a crafted `lang` could inject a key the indexer would then prefer.
The separation of concerns was the defect. One JSON writer, here.

WHY SANITISE RATHER THAN ESCAPE. Correct JSON escaping is what a normal writer would do, and it
would break the reader: `jf()` in kit-index.sh matches `"[^"]*"` and cannot see past a `\"`. So
every string field is stripped of quote, backslash and control characters BEFORE serialisation,
which makes the emitted line both valid JSON and readable by that awk. `_assert_flat()` then
checks the invariant on the finished line rather than trusting the sanitiser.

WHY NO JSON SCHEMA FILE. One was built and deleted. `jsonschema` is not installed and the kit
promises no runtime dependencies, so a schema file meant hand-writing a subset interpreter of a
standard -- a second implementation, and a THIRD way to declare config beside the project
profile and the `--vocab` accessor. CONTRACT below is the one definition; `kit-finding.sh
--contract` is the door.

WHAT IS NOT CONFIGURABLE. `class` and `severity` are a SHARED taxonomy: the accelerators
aggregate findings across projects, and a per-project class list would make that meaningless.
`domain` is the axis that IS project-specific, and it is declared in the project profile.

Usage:
    kit_findings.py --contract                     the contract, for humans and agents
    kit_findings.py --validate         < json      exit 0 accepted, 2 rejected
    kit_findings.py --emit-events      < json      complete NDJSON event lines on stdout
        --task ID | --unattributed, --agent NAME, [--agent-id X] [--model M]
        [--industries "bfsi govtech"]  domains outside this list are dropped, as declared

`--emit-events` prints NOTHING unless every finding passed, so the caller can append its whole
output in one operation. A half-stored review is a finding table that disagrees with the review
it came from, and afterwards nobody can tell which half is missing.
"""
import datetime
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# THE definition of a finding's shape. One home. Every consumer asks for it.
#   name -> (required, type, min, max, why)
CONTRACT = (
    ("class",    True,  str, 1, 40,
     "what kind of defect. Vocabulary from `kit-finding.sh --vocab`."),
    ("severity", True,  str, 1, 20,
     "how bad. Vocabulary from `kit-finding.sh --vocab`."),
    ("summary",  True,  str, 8, 200,
     "one line naming the defect. Required because without it a row is a bare counter: "
     "seven findings recorded on 2026-08-10 all read `fail-open|major|bash` and could not "
     "be told apart afterwards."),
    ("lang",     False, str, 0, 40,
     "seeds the technology accelerator. Blank rather than guessed."),
    ("pattern",  False, str, 0, 60,
     "the reusable DESIGN this is about, independent of language and industry "
     "(cache-port, retry-budget). Blank rather than guessed."),
    ("domain",   False, str, 0, 40,
     "an INDUSTRY, dropped unless this project declared one. Blank unless known."),
    ("file",     False, str, 0, 200,
     "path the finding is anchored to."),
    ("line",     False, int, 1, None,
     "1-indexed line in that file."),
)

ALLOWED = tuple(c[0] for c in CONTRACT)

# Which fields carry a closed vocabulary. The field NAMES live here; the vocabulary itself does
# not, and must not -- it has one home and this file asks that home for it.
VOCAB_FIELDS = ("class", "severity")

TYPE_NAME = {str: "string", int: "integer"}

_UNSAFE = re.compile(r'[\\"]')
_CONTROL = re.compile(r"[\x00-\x1f\x7f]+")


class Rejected(Exception):
    pass


def sanitise(text):
    """One line, printable, no quote and no backslash. Applied to EVERY string that reaches the
    log, not only `summary` -- restricting it to `summary` was the critical both reviewers
    found. Lossy by one character class, and honest about it."""
    return " ".join(_UNSAFE.sub("'", _CONTROL.sub(" ", text)).split())


def _assert_flat(line):
    """The invariant the awk reader depends on, checked on the finished line rather than
    assumed from the sanitiser. A backslash here means some field escaped sanitisation, and the
    row it produces would be silently truncated or mis-keyed on the way back in."""
    if "\\" in line:
        raise Rejected("internal: a backslash survived into the event line; refusing to write.\n"
                       "  The awk reader cannot see past it and the row would be corrupt.")
    if "\n" in line or "\r" in line:
        raise Rejected("internal: a newline survived into the event line; refusing to write.")


def vocabularies():
    """The one definition, asked for rather than restated."""
    try:
        out = subprocess.run(
            ["bash", os.path.join(HERE, "kit-finding.sh"), "--vocab"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        # A hung or missing shell must not hang or crash the recorder. It must say so.
        raise Rejected("could not run `kit-finding.sh --vocab`: %s" % exc)
    if out.returncode != 0:
        raise Rejected("`kit-finding.sh --vocab` failed: %s"
                       % out.stderr.decode("utf-8", "replace").strip())
    vocab = {}
    for line in out.stdout.decode("utf-8", "replace").splitlines():
        if ":" in line:
            name, words = line.split(":", 1)
            vocab[name.strip()] = words.split()
    for field in VOCAB_FIELDS:
        if not vocab.get(field):
            raise Rejected("`kit-finding.sh --vocab` named no %r vocabulary" % field)
    return vocab


def kind_of(node):
    if node is None:
        return "null"
    if isinstance(node, bool):
        return "boolean"
    return {dict: "object", list: "array", str: "string", int: "integer",
            float: "number"}.get(type(node), type(node).__name__)


def check_finding(finding, index, errors):
    where = "findings[%d]" % index
    if not isinstance(finding, dict):
        errors.append("%s: expected an object, got %s" % (where, kind_of(finding)))
        return
    for key in finding:
        if key not in ALLOWED:
            errors.append("%s: unknown field %r (allowed: %s)"
                          % (where, key, ", ".join(ALLOWED)))
    for name, required, want, low, high, _why in CONTRACT:
        if name not in finding:
            if required:
                errors.append("%s: missing required field %r" % (where, name))
            continue
        value = finding[name]
        # bool is an int in Python and would pass an integer check; JSON says otherwise.
        if isinstance(value, bool) or not isinstance(value, want):
            errors.append("%s.%s: expected %s, got %s"
                          % (where, name, TYPE_NAME[want], kind_of(value)))
            continue
        if want is str:
            if low and len(value) < low:
                errors.append("%s.%s: %d characters, minimum %d%s"
                              % (where, name, len(value), low,
                                 " -- say what the defect IS" if name == "summary" else ""))
            if high and len(value) > high:
                errors.append("%s.%s: %d characters, maximum %d"
                              % (where, name, len(value), high))
        elif want is int:
            if low is not None and value < low:
                errors.append("%s.%s: %s is below minimum %s" % (where, name, value, low))


_FENCE = re.compile(r"\A\s*```[A-Za-z0-9_-]*\s*\n(?P<body>.*)\n\s*```\s*\Z", re.S)


def unfence(text):
    """Strip ONE surrounding markdown code fence, if the whole payload is wrapped in it.

    The single concession to how models actually reply, and it was earned: told in capitals to
    emit no fence, a live reviewer wrapped its object in ```json anyway. It is not the
    prose-scraping this design deletes, and the difference is the failure mode. Every FIELD
    still comes from a JSON parse. If this unwrap guesses wrong the result is `not valid JSON`
    and nothing is recorded, never a row that is quietly the wrong value. Prose around an object
    is left alone and fails loudly -- which it did, on a real review, on 2026-08-11.
    """
    m = _FENCE.match(text)
    return m.group("body") if m else text


def validate(payload_text):
    try:
        doc = json.loads(unfence(payload_text))
    except ValueError as exc:
        raise Rejected("not valid JSON: %s\n"
                       "  The whole reply must be one JSON object. A fenced object is "
                       "unwrapped; prose around it is not." % exc)

    if not isinstance(doc, dict):
        raise Rejected("  top level: expected an object, got %s" % kind_of(doc))
    if "findings" not in doc:
        raise Rejected("  top level: missing required field 'findings'\n"
                       "  A reviewer that found nothing sends []. Omitting the key is not "
                       "the same statement, and only one of them is a measurement.")
    # `verdict` and `narrative` ride along so a reviewer returns ONE object and nothing has to
    # pull a fenced block out of markdown. Accepted and ignored here: this module records
    # findings; the verdict is for the human who decides whether the work closes.
    for key in doc:
        if key not in ("findings", "verdict", "narrative"):
            raise Rejected("  top level: unknown field %r (allowed: findings, verdict, "
                           "narrative)" % key)
    for key in ("verdict", "narrative"):
        if key in doc and not isinstance(doc[key], str):
            raise Rejected("  top level: %r must be a string, got %s"
                           % (key, kind_of(doc[key])))
    if not isinstance(doc["findings"], list):
        raise Rejected("  findings: expected an array, got %s" % kind_of(doc["findings"]))

    # Every failure is collected. A reviewer fixing one error per round trip is how a review
    # stops being worth running.
    errors = []
    for i, finding in enumerate(doc["findings"]):
        check_finding(finding, i, errors)
    if errors:
        raise Rejected("\n".join("  " + e for e in errors))

    vocab = vocabularies()
    for i, finding in enumerate(doc["findings"]):
        for field in VOCAB_FIELDS:
            if finding[field] not in vocab[field]:
                errors.append("  findings[%d].%s: %r is not in the %s vocabulary (%s)"
                              % (i, field, finding[field], field, " ".join(vocab[field])))
    if errors:
        raise Rejected("\n".join(errors))

    rows = []
    for finding in doc["findings"]:
        row = {}
        for name, _req, want, low, _high, _why in CONTRACT:
            if name not in finding:
                continue
            row[name] = sanitise(finding[name]) if want is str else finding[name]
        if len(row["summary"]) < 8:
            raise Rejected(
                "  a summary became too short after normalisation: %r\n"
                "  Quotes and backslashes are replaced; write the line without them."
                % finding["summary"])
        rows.append(row)
    return rows


def build_events(rows, opts):
    """Complete event lines. json.dumps is the only thing that serialises a finding."""
    at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    industries = opts["industries"]
    lines = []
    for row in rows:
        domain = row.get("domain", "")
        if domain and industries is not None and domain not in industries:
            sys.stderr.write(
                "kit-findings: domain %r is not declared in accelerator.industry -- dropped\n"
                "  (a domain is an industry; put the reusable design in `pattern`)\n" % domain)
            domain = ""
        event = {
            # `task` is sanitised like every other string. It was NOT, for one round: it sat
            # raw beside sanitise(agent) on this very line while the docstring claimed the
            # sanitiser covered everything reaching the log. Both round-4 reviewers found it.
            "task": sanitise(opts["task"]), "kind": "finding", "at": at,
            "agent": sanitise(opts["agent"]), "agent_id": sanitise(opts["agent_id"]),
            "class": row["class"], "severity": row["severity"],
            "lang": row.get("lang", ""), "pattern": row.get("pattern", ""),
            "domain": domain, "model": sanitise(opts["model"]),
            "file": row.get("file", ""),
            # A BARE integer: the reader (jn() in kit-index.sh) matches `"line": <digits>` and
            # would never see a quoted one. 0 means "not supplied" and maps back to NULL there.
            "line": row.get("line", 0),
            "summary": row["summary"],
        }
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
        _assert_flat(line)
        lines.append(line)
    return lines


# Why a gap carries a REASON rather than only a count: the two cases mean opposite things. A
# review that looked and found nothing is evidence; a review whose findings were REJECTED is a
# measurement hole, and the findings still exist in the reviewer nobody kept. Reporting them as
# one number is how `T3 0/13` came to read as "nothing escaped" when it meant "nothing was
# recorded". `empty` and `rejected` are the whole vocabulary.
GAP_REASONS = ("empty", "rejected")


def gap_event(opts, reason):
    """Absence is a measurement. A review that recorded nothing must be visible as a fact, not
    as silence."""
    if reason not in GAP_REASONS:
        raise Rejected("internal: unknown gap reason %r (one of: %s)"
                       % (reason, " ".join(GAP_REASONS)))
    at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    event = {"task": sanitise(opts["task"]), "kind": "finding-gap", "at": at,
             "agent": sanitise(opts["agent"]), "agent_id": sanitise(opts["agent_id"]),
             "reason": reason}
    line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
    _assert_flat(line)
    return line


def resolve_event(argv):
    """Whether a finding was ADDRESSED. Orthogonal to `vindicated`, which says whether it was
    real -- both facts exist, and one column cannot hold two.

    Serialised HERE and nowhere else for the reason every other event line is: the shell used to
    build these with printf, and a single quote in a value corrupts an append-only committed log
    permanently. The finding id is the only field the reader keys on, so it is the one that most
    needs to arrive intact."""
    opts = {"finding": "", "fixed": "", "commit": "", "note": "", "at": ""}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a[2:].replace("-", "_") in opts and a.startswith("--"):
            if i + 1 >= len(argv):
                raise Rejected("%s needs a value" % a)
            opts[a[2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            raise Rejected("unknown argument %s" % a)
    if not opts["finding"]:
        raise Rejected("--finding is required (the id from kit-resolve.sh --list)")
    if opts["fixed"] not in ("0", "1"):
        raise Rejected("--fixed must be 0 or 1; there is no third state")
    # SUB-SECOND, and stamped here rather than by the caller. Marks on one finding are applied
    # last-write-wins over events sorted by `at`, and at whole-second resolution a fix and a
    # reopen recorded in the same second are ORDER-AMBIGUOUS: the tie breaks on the text of the
    # line, where `"fixed":0}` sorts before `"fixed":1,"commit":...`, so the retraction is
    # applied first and the fix wins. The retraction silently does nothing.
    #
    # Not hypothetical and not caught by review: it passed on the machine it was written on,
    # where the two commands are a second apart, and failed in a container fast enough to put
    # them in one second. `date -u` cannot help -- BSD date has no %N and this runs on macOS.
    if not opts["at"]:
        opts["at"] = datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%S.%fZ")
    event = {"kind": "finding-fixed", "at": sanitise(opts["at"]),
             "finding": sanitise(opts["finding"]), "fixed": int(opts["fixed"])}
    # Omitted rather than written empty: an absent key reads as "not supplied", where
    # `"commit":""` reads as a commit that was supplied and is blank.
    for k in ("commit", "note"):
        if opts[k]:
            event[k] = sanitise(opts[k])
    line = json.dumps(event, ensure_ascii=False, separators=(",", ":"))
    _assert_flat(line)
    return line


# The correction handed back to a reviewer whose reply was refused. Deterministic on purpose:
# the diagnostics are the validator's own, not a description of them composed by a model, so a
# retry cannot drift away from what was actually wrong. Four live runs produced three different
# non-compliances (a reporting tool, a preamble, an over-long summary), which is the evidence
# that a system-prompt instruction is a request and not a mechanism.
# The retry prompt carries THE ORIGINAL REQUEST and THE PREVIOUS REPLY, and does not replace
# them. It used to be the diagnostics alone, which is incoherent for a stateless reviewer: the
# second attempt received "send the SAME review again" with no request to review from and no
# copy of the reply it was being asked to resend. One reviewer re-derived from its tools and
# looked fine; the next returned `{"findings":[]}`, which recorded as `reason=empty` -- "a
# review looked and found nothing". It had not looked. The loop built to stop false cleans
# manufactured one. Observed 2026-08-12 by running a real round through it.
CORRECTION = """%(original)s

======================================================================
The request above still stands. This is a RETRY.

Your previous reply was REFUSED by the findings contract and NOTHING was recorded. Do not \
apologise or explain; send the corrected object only.

What was wrong:
%(errors)s

Your previous reply, for reference:
----------------------------------------------------------------------
%(previous)s
----------------------------------------------------------------------

Send that same review again with those problems fixed. Your entire reply must be one JSON \
object: the first character is { and the last is }. No preamble, no code fence, no text \
before or after it. Keep every `summary` under 200 characters -- put the explanation in \
`narrative`, which has no limit."""


def print_contract():
    sys.stdout.write("finding object fields (JSON, one object per finding under `findings`):\n")
    for name, required, want, low, high, why in CONTRACT:
        bound = ""
        if want is str and (low or high):
            bound = " %s-%s chars" % (low, high)
        elif want is int and low is not None:
            bound = " min %s" % low
        sys.stdout.write("  %-9s %-8s %-9s%s\n      %s\n" % (
            name, "required" if required else "optional", TYPE_NAME[want], bound, why))
    sys.stdout.write(
        "\nThe reply is ONE object: {\"verdict\": ..., \"narrative\": ..., \"findings\": [...]}\n"
        "Unknown fields are rejected, and a rejected batch records NOTHING -- a half-stored\n"
        "review is a finding table that disagrees with the review it came from.\n")


def parse_opts(argv):
    opts = {"task": "", "agent": "", "agent_id": "", "model": "",
            "industries": None, "unattributed": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--task", "--agent", "--agent-id", "--model", "--industries"):
            if i + 1 >= len(argv):
                raise Rejected("%s needs a value" % a)
            key = a[2:].replace("-", "_")
            opts["industries" if a == "--industries" else key] = argv[i + 1]
            i += 2
        elif a == "--unattributed":
            opts["unattributed"] = True
            i += 1
        else:
            raise Rejected("unknown argument %s" % a)
    if opts["industries"] is not None:
        opts["industries"] = opts["industries"].split()
    if not opts["agent"]:
        raise Rejected("--agent is required")
    if not opts["task"] and not opts["unattributed"]:
        raise Rejected("--task is required (or --unattributed if the caller cannot know it)")
    if opts["task"] and opts["unattributed"]:
        raise Rejected("--task and --unattributed are contradictory; refusing rather than "
                       "picking one")
    return opts


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--validate"
    if mode == "--contract":
        print_contract()
        return 0
    if mode not in ("--validate", "--emit-events", "--gap-event", "--correction", "--resolve"):
        sys.stderr.write("kit-findings: unknown mode %s\n" % mode)
        return 2
    # Dispatched before stdin is touched: this mode reads none, and a mode that blocks on a
    # terminal it was never given looks exactly like a hang.
    if mode == "--resolve":
        try:
            sys.stdout.buffer.write((resolve_event(sys.argv[2:]) + "\n").encode("utf-8"))
        except Rejected as exc:
            sys.stderr.write("kit-findings: %s\n" % exc)
            return 2
        return 0
    # Exit 3, distinctly from 2: "this is retryable and here is the exact text to send back",
    # versus "this call was wrong". A caller that cannot tell them apart will retry a usage
    # error forever.
    if mode == "--correction":
        # --original-file carries the request the reviewer was answering. Without it the retry
        # is a correction with nothing to correct, which is how an empty review came to be
        # recorded as a measurement.
        original = ""
        if "--original-file" in sys.argv:
            path = sys.argv[sys.argv.index("--original-file") + 1]
            try:
                with open(path, encoding="utf-8") as fh:
                    original = fh.read()
            except (OSError, UnicodeDecodeError) as exc:
                sys.stderr.write("kit-findings: cannot read --original-file: %s\n" % exc)
                return 2
        if not original.strip():
            sys.stderr.write(
                "kit-findings: --correction needs --original-file with the request the "
                "reviewer was answering.\n  A retry that drops the request asks a stateless "
                "reviewer to resend a review it cannot see.\n")
            return 2
        payload = sys.stdin.read()
        try:
            validate(payload)
            return 0
        except Rejected as exc:
            sys.stdout.write(CORRECTION % {
                "original": original.rstrip(),
                "errors": str(exc).rstrip(),
                "previous": payload.strip() or "(your previous reply was empty)",
            })
            return 3
    try:
        # `--gap-event` reads no stdin: it is called AFTER a rejection has already consumed it,
        # so that the one case where findings are genuinely lost leaves a row rather than a
        # stderr line nobody will find again.
        if mode == "--gap-event":
            opts = parse_opts(sys.argv[3:])
            sys.stdout.buffer.write((gap_event(opts, sys.argv[2]) + "\n").encode("utf-8"))
            return 0
        opts = parse_opts(sys.argv[2:]) if mode == "--emit-events" else None
        rows = validate(sys.stdin.read())
        if mode == "--emit-events":
            lines = build_events(rows, opts) if rows else [gap_event(opts, "empty")]
            # One write. Nothing partial reaches the caller, so nothing partial reaches the log.
            sys.stdout.buffer.write(("\n".join(lines) + "\n").encode("utf-8"))
    except Rejected as exc:
        sys.stderr.write("kit-findings: rejected, nothing recorded.\n%s\n" % exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
