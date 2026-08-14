# Models

Which models the agents run on, how to point them somewhere else, and one rule that must
not be broken.

## The agents pin tiers, not products

Each agent declares a model in its frontmatter:

| Agent | `model:` | Why |
|---|---|---|
| `researcher`, `approach-reviewer`, `security-reviewer` | `opus` | design alternatives and adversarial reading, where a missed failure mode is expensive |
| `coder`, `implementation-reviewer`, `tester`, `adr-scribe`, `documenter` | `sonnet` | the working tier — most of the volume |

`documenter` was `haiku`, justified as "mechanical, high-volume, low-judgement". **The
justification was wrong about its scope.** It writes README and topic sub-docs — audience-facing
prose, where the judgement is deciding what a reader needs, at what depth, in what register, and
what to leave out. That is not mechanical, and it is high-ambiguity even though its blast radius
is small.

It matters more than a tier row because of what the documentation *is*: the delivered application
must be maintainable without any AI tooling, by developers, as-is — so the docs are not a
description of the deliverable, they are half of it. Under-tiering the agent that writes half the
inheritance is the wrong economy, and cheap prose is expensive twice: once when it is written and
again for everyone who maintains from it.

Cost is still a real constraint. If this tier proves expensive in volume, the answer is to **split
the work by audience, not to lower the tier across it** — mechanical updates (CHANGELOG entries,
docstring stubs) can sit on a cheaper tier than prose a stranger has to learn from.

`opus`, `sonnet` and `haiku` are **aliases**, not model IDs. `ANTHROPIC_DEFAULT_OPUS_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` control what each one
resolves to. So an operator remaps all eight agents by setting three environment variables,
without touching the plugin.

What the agents actually depend on is the **three-tier split** — deep reasoning, working,
cheap — and the routing between them is what `tier-classify` exists to decide.

## The rule: never pin a full model ID in agent frontmatter

Writing `model: claude-opus-4-8` instead of `model: opus` converts a remappable alias into
a hard dependency for every operator downstream. It cannot be overridden by environment,
it does not follow a version upgrade, and on Bedrock, Google Cloud's Agent Platform or
Microsoft Foundry — where the same model is addressed by an inference profile ARN, a
version name or a deployment name — it does not resolve at all.

The pin belongs in the operator's environment, where it can differ per deployment. Not in a
file that ships to everyone.

## Pointing the kit at your own endpoint

```sh
export ANTHROPIC_BASE_URL=https://your-gateway.example.com
export ANTHROPIC_AUTH_TOKEN=...
export ANTHROPIC_DEFAULT_OPUS_MODEL=...      # what the opus-tier agents resolve to
export ANTHROPIC_DEFAULT_SONNET_MODEL=...
export ANTHROPIC_DEFAULT_HAIKU_MODEL=...
```

Nothing in the kit needs to change. There is no model configuration in
`project-profile.md`, deliberately: the profile is committed and shared, and which endpoint
a developer reaches is a property of their machine, not of the project.

## The boundary: non-Claude models

Claude Code accepts three wire formats:

| Format | Selected by | Endpoint |
|---|---|---|
| Anthropic Messages | `ANTHROPIC_BASE_URL` | `/v1/messages` |
| Amazon Bedrock InvokeModel | `ANTHROPIC_BEDROCK_BASE_URL` + `CLAUDE_CODE_USE_BEDROCK=1` | `/model/{model}/invoke` |
| Google Cloud Agent Platform | `ANTHROPIC_VERTEX_BASE_URL` + `CLAUDE_CODE_USE_VERTEX=1` | `:rawPredict` |

OpenAI's `/v1/chat/completions` is not among them. An OpenAI-compatible endpoint therefore
cannot be used directly: bridging the two would mean rewriting request and response bodies,
which is a proxy, and no configuration avoids it.

Two further constraints make this a boundary rather than a gap to engineer around:

- Gateway model discovery **ignores entries whose `id` does not begin with `claude` or
  `anthropic`**, so a compliant gateway still will not surface other vendors' models.
- Routing Claude Code to non-Claude models through a gateway is explicitly unsupported.

If the endpoint you are given *does* speak Anthropic Messages — many gateway products
expose exactly that — everything above works today with no plugin change at all.

## What this costs

`claude --plugin-dir . plugin details coding-kit` reports the current split. Agent
descriptions are resident because that is how routing works, so the eight agents are
~840 tok of the ~1,259 tok always-on cost regardless of which models back them.

Changing what an alias resolves to does not change that number. Adding a ninth agent does.
