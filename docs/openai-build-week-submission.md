# AkuBrowser - a finite, user-steered layer over infinite feeds

## Inspiration

Attention is what everyone is fighting for right now. With the rise of For You
Pages, social platforms are built around infinite feeds: there is always
another post, another notification, and another reason to keep scrolling.
Access to information has improved, but consuming it has become exhausting.

I want to give control back to the user: which topics deserve attention, which
information they want to see more or less of, and when they have consumed
enough. AkuBrowser makes that direction concrete through user-owned preference
filtering, cross-source semantic reasoning that reduces repeated reports, and
an optional AI Signals layer for people who want to see less AI-origin content.

The browser remains humanity's gateway to online knowledge. As websites,
agents, and MCP servers increasingly communicate with us and with one another,
we will need a new kind of browser where the user, not a server-side algorithm,
retains authority over attention.

## What it does

Instead of passively accepting everything pushed into a timeline, AkuBrowser
helps users filter and prioritize what is relevant to them. It works with the
user's existing authenticated Chrome session, treats the platform feed order
as a borrowed behavioral prior, and builds a local, user-owned preference and
reasoning layer on top of it. It currently supports X, Facebook, and LinkedIn.

> Show me what matters to me, explain why it matters, preserve the sources,
> and let me feel finished.

A typical session:

1. Captures a bounded set of posts from the user's authenticated X, Facebook,
   and LinkedIn feeds.
2. Validates each observation while preserving its metadata and original
   context.
3. Skips unchanged posts or evidence that has already been delivered.
4. Uses Codex for **Acquisition Planning** to determine whether the available
   evidence is sufficient or whether one additional bounded observation would
   be useful.
5. Uses Codex for **Candidate Evaluation** to describe each candidate's topics,
   materiality, novelty, urgency, actionability, and evidence strength.
6. Combines those assessments with the user's explicit interests and locally
   learned preferences.
7. Filters candidates according to the user's attention policy.
8. Uses Codex for **cross-source semantic reasoning** when needed to recognize
   posts about the same event, collapse repeated reports, and preserve
   meaningful updates or different perspectives.
9. Composes the selected events into one finite, personalized Timeline.
10. Applies local AI Fast Detection and Codex-backed **AI Deep Detection** to
    retained posts. Depending on the user's preference, strong signals can
    remain inline, move to a dedicated drawer, or be hidden after explicit
    confirmation.
11. Ends with a clear **End of catch-up** marker.

AkuBrowser learns through explicit interaction rather than passive
surveillance. Preference-based filtering and ranking are applied through
deterministic application policy, and the user remains the final authority.

## How we built it

AkuBrowser is divided into independent components:

- **AkuBridge** is a read-only Chrome extension. It performs bounded capture,
  source-specific quality checks, and sends structured evidence to AkuSidecar.
- **AkuSidecar** is a local Go application. It owns the UI, SQLite persistence,
  session orchestration, deterministic selection, preference policy, and one
  managed Codex App Server process for Acquisition Planning, Candidate
  Evaluation, Semantic Event Resolution, and AI Deep Detection.
- **AkuBrowser** is the main product and integration repository. It owns the
  architecture, canonical contracts, compatibility checks, Windows packaging,
  and aggregate development workflows.
- **AkuSupervisor** is an optional Rust lifecycle tool for development. It owns
  visible process lifecycle, health, bounded logs, and cooperative AkuBridge
  reload. Its current MCP runtime surface is deliberately read-only; start,
  stop, and restart remain authenticated CLI/HTTP actions rather than MCP tools.

The authority boundary is intentional: AkuBridge observes, Codex reasons, and
AkuSidecar controls policy, validation, state, and final composition.
AkuSupervisor reduces repeated development overhead by giving humans and agents
structured, auditable runtime evidence. It may eventually be bundled as the
local lifecycle engine responsible for launching and maintaining AkuSidecar.

## What we built during OpenAI Build Week

The idea became practical for me with GPT-5.6, especially Sol, and OpenAI Build
Week created the opportunity to push the project from an early prototype toward
a working product. During the submission period, Codex helped across
architecture, implementation, live debugging, regression testing,
documentation, and release preparation in every repository.

The Build Week work includes:

- rewriting AkuSidecar from Node.js to Go while preserving SQLite state,
  recovery, and product behavior;
- integrating Codex App Server for Acquisition Planning, Candidate Evaluation,
  cross-source Semantic Event Resolution, and AI Deep Detection, with
  process-specific GPT-5.6 profiles and local usage telemetry;
- implementing preference-aware selection with calibration, More/Less
  feedback, local learning, candidate filtering, and correction controls;
- building a cross-source Semantic Event Engine that collapses repeated reports
  while preserving updates, contradictions, and different perspectives;
- expanding bounded, source-faithful capture to X, LinkedIn, and Facebook with
  shared quality, freshness, media, and lifecycle controls;
- adding AI Fast and Deep Detection with user-controlled Inline, Drawer, and
  explicitly confirmed Hide modes;
- strengthening onboarding, session recovery, exact-evidence suppression,
  resurfacing, reset, and Sidecar-restart behavior;
- packaging a verifiable Windows x64 portable preview with launchers,
  provenance, checksums, and a bundled unpacked AkuBridge payload; and
- extending AkuSupervisor with lifecycle ownership, cooperative Bridge reload,
  health and log monitoring, read-only MCP support, and synchronized
  cross-repository regression tests.

The dated Git history and [`BUILD_WEEK.md`](../BUILD_WEEK.md) distinguish the
pre-existing prototype from the capabilities added or materially extended
during the competition.

## Challenges we ran into

One of the hardest challenges was preserving source fidelity. Modern social
sites are dynamic, and Chrome extension service workers can stop and restart.
We built source-specific adapters, bounded retries, durable checkpoints,
idempotent commands, and recovery paths so a partial capture or Sidecar restart
does not corrupt a session or lose the source-native reading experience.

Preference filtering introduced a different challenge: information can be
objectively material without being personally relevant. Codex describes the
content, while explicit interests and feedback determine how it competes for
limited attention. Cross-source semantic reasoning must then reduce repetition
without merging genuine updates or different perspectives, while AI filtering
must remain uncertain, explainable, and user-controlled.

Security, cost, and packaging were equally important. Web content is untrusted
evidence, so it is isolated from trusted instructions, every model response is
validated, and browser movement and filtering authority remain deterministic.
Development and runtime reasoning also compete for limited Codex tokens, which
made model selection and usage telemetry part of the engineering work. Finally,
the local stack spans Chrome, Go, SQLite, Codex, and Rust, so packaging it behind
one clear Windows entry point became a product challenge of its own.

## Accomplishments that we are proud of

We are most proud that our original idea—giving control of attention back to
the user—became an enforceable product rather than only a design promise.
AkuBrowser combines bounded capture from authenticated X, Facebook, and
LinkedIn feeds with structured Codex reasoning, user-owned preference
filtering, cross-source semantic event resolution, knowledge continuity, AI
Signals, and one finite Timeline.

We are also proud that a broad and ambitious idea became a working prototype in
only a few weeks. Even a full rewrite of AkuSidecar into a different language
and reasoning protocol became manageable when the work was divided into clear
contracts and validated slices. That experience also taught us that disciplined
token management is now an important part of AI-assisted product development.

## What we learned

We learned that AI works best when probabilistic reasoning is surrounded by
deterministic boundaries. Codex can understand meaning, context, and evidence,
but permissions, browser movement, preference authority, validation, and state
must remain under application control. The user must always be able to inspect,
correct, or override the result.

AI-assisted development also does not mean letting AI lead every decision. It
can spend time and tokens in the wrong direction if product boundaries are
unclear. The developer still owns the specification, architecture, acceptance
criteria, and trade-offs; careful model and token use is essential to shipping.

Most importantly, the gap between an idea and a working proof of concept is
smaller than it used to be. Difficult ideas can now be tested quickly when the
specification is sliced into explicit, verifiable steps. A proof of concept is
therefore not only faster to build, but also a practical way to discover whether
the original idea is useful and feasible.

## What's next for AkuBrowser

AkuBrowser currently provides a Windows x64 portable preview for X, Facebook,
and LinkedIn. The package includes AkuBridge and AkuSidecar; AkuSupervisor
remains separate development tooling. Our immediate next step is to simplify
installation and updates through one guided product experience and evaluate
bundling AkuSupervisor as the local lifecycle engine.

Future versions will support more social platforms, other websites, additional
media types, and eventually macOS and Linux. The adapter architecture will
become more generic and reusable without sacrificing source fidelity,
preference authority, provenance, quiet capture, explicit consent, or the clear
finish line.

The longer-term goal is to rethink how people consume information in an age of
websites, agents, and MCP servers. Discovery, transactions, recommendations,
and advertising may increasingly be mediated by agents, while some people will
still want spaces reserved for direct human interaction. AkuBrowser is an
attempt to preserve the human choice of what deserves attention, how it is
consumed, and when to stop. We hope Build Week is the first step toward bringing
that vision to a broader public.
