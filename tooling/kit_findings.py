#!/usr/bin/env python3
"""Read and validate reviewer findings. The JSON boundary, in one place.

Reviewers used to return a prose block that something -- a hook scraping a transcript, or a
person reading the markdown and retyping it -- had to parse back into fields. Every defect in
that path came from the parsing: an envelope leaking into the log, backslash corruption,
retracted drafts recorded as real. The fix is not a better parser. The reviewer returns data.

Python rather than shell because `python3` is already a hard dependency (validate.py runs in
CI), so the constraint that once justified hand-rolling JSON with awk and sed was never real
-- docs/LESSONS.md S7.

WHY NOT A JSON SCHEMA FILE. It was built and deleted. `jsonschema` is not installed and the
kit promises no runtime dependencies, so a schema file meant hand-writing a subset interpreter
of a standard -- a second implementation, and a THIRD way to declare config beside the project
profile and the `--vocab` accessor. This kit's standard is one definition in the tool, reached
through a command, referenced and never restated by its consumers. CONTRACT below is that one
definition; `kit-finding.sh --contract` is the door. Reconsider a schema file only when
something other than this validator needs to consume it.

WHAT IS NOT CONFIGURABLE, AND WHY. `class` and `severity` are a SHARED taxonomy: the
accelerators aggregate findings across projects, and a per-project class list would make that
aggregation meaningless. They stay in one home for every project. `domain` is the axis that IS
project-specific, and it is already declared in the project profile. That split is deliberate.

Usage:
    kit_findings.py --validate      < findings.json    exit 0 accepted, 2 rejected
    kit_findings.py --emit-fields   < findings.json    TSV of normalised fields
    kit_findings.py --contract                         the contract, for humans and agents

Nothing is written here: this module decides, `kit-finding.sh` records. A validator that could
also write would be the second thing with an opinion about what a finding is.
"""
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

# Which fields carry a closed vocabulary. The field NAMES live here; the vocabulary itself
# does not, and must not -- it has one home and this file asks that home for it.
VOCAB_FIELDS = ("class", "severity")

TYPE_NAME = {str: "string", int: "integer"}


class Rejected(Exception):
    pass


def vocabularies():
    """The one definition, asked for rather than restated."""
    out = subprocess.run(
        ["bash", os.path.join(HERE, "kit-finding.sh"), "--vocab"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if out.returncode != 0:
        raise Rejected("could not read the vocabulary from `kit-finding.sh --vocab`")
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


# A summary is free text from a reviewer, and it is read back out of events.ndjson by an awk
# extractor whose pattern is "[^"]*" -- it cannot see past an escaped quote, and a backslash
# corrupted a field in this repo once already. Rather than leave that landmine for a later
# reader, the writer normalises: one line, printable, no quote and no backslash. Lossy by one
# character class, and honest about it, which the alternative was not.
_UNSAFE = re.compile(r'[\\"]')
_CONTROL = re.compile(r"[\x00-\x1f\x7f]+")


def normalise_summary(text):
    return " ".join(_UNSAFE.sub("'", _CONTROL.sub(" ", text)).split())


_FENCE = re.compile(r"\A\s*```[A-Za-z0-9_-]*\s*\n(?P<body>.*)\n\s*```\s*\Z", re.S)


def unfence(text):
    """Strip ONE surrounding markdown code fence, if the whole payload is wrapped in it.

    This is the single concession to how models actually reply, and it was earned: told in
    capitals to emit no fence, a live reviewer wrapped its object in ```json anyway. It is not
    the prose-scraping this design deletes, and the difference is the failure mode. Every
    FIELD still comes from a JSON parse -- all-or-nothing, vocabulary-checked. If this unwrap
    ever guesses wrong the result is `not valid JSON` and nothing is recorded, never a row
    that is quietly the wrong value. Anything other than a single wrapping fence is left
    alone, so prose around an object still fails loudly instead of being mined for fields.
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
    # pull a fenced block out of markdown -- that extraction is the prose parsing this design
    # exists to delete. They are accepted and ignored here: this module records findings, and
    # the verdict is for the human who decides whether the work closes. No vocabulary is
    # enforced on `verdict` because nothing downstream reads it yet, and a check nothing needs
    # is a check that will drift unnoticed.
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
        row = dict(finding)
        row["summary"] = normalise_summary(finding["summary"])
        if len(row["summary"]) < 8:
            raise Rejected(
                "  a summary became too short after normalisation: %r\n"
                "  Quotes and backslashes are replaced; write the line without them."
                % finding["summary"])
        rows.append(row)
    return rows


# US (0x1f), not tab. Tab is IFS *whitespace*, and the shell collapses runs of it, so six
# consecutive empty fields arrive as one and every value after them shifts left -- observed:
# a summary landed in `lang` and the row was written with the wrong columns. A non-whitespace
# separator has no such rule, and normalise_summary strips every control character, so this
# byte cannot appear inside a value.
SEP = "\x1f"


def emit_fields(rows):
    """One record per line for the shell recorder. Written to the BYTE stream on purpose:
    Python's text mode translates \\n to os.linesep, which on Windows put a CR inside the JSON
    string the recorder then wrote to the append-only log -- and a lone CR is read back as a
    line break, splitting one event across two malformed lines."""
    out = []
    for row in rows:
        out.append(SEP.join([
            row["class"], row["severity"], row.get("lang", ""), row.get("pattern", ""),
            row.get("domain", ""), row.get("file", ""), str(row.get("line", "")),
            row["summary"],
        ]))
    if out:
        sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))


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
        "\nUnknown fields are rejected, and a rejected batch records NOTHING -- a half-stored\n"
        "review is a finding table that disagrees with the review it came from.\n")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--validate"
    if mode == "--contract":
        print_contract()
        return 0
    if mode not in ("--validate", "--emit-fields"):
        sys.stderr.write("kit-findings: unknown mode %s\n" % mode)
        return 2
    try:
        rows = validate(sys.stdin.read())
    except Rejected as exc:
        sys.stderr.write("kit-findings: rejected, nothing recorded.\n%s\n" % exc)
        return 2
    if mode == "--emit-fields":
        emit_fields(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
