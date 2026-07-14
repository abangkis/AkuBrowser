# AkuBrowser release checkpoint — 2026-07-14

> Decision: **PASS** for the current personal X + LinkedIn pilot.
>
> Recorded in Asia/Jakarta after live acceptance, lifecycle recovery, contract,
> package, and automated-test validation.

## Release identity

The four repositories version independently. This checkpoint is identified by
the following compatible tuple; equal package versions are not required.

| Component | Version / build | Code baseline | Release tag |
| --- | --- | --- | --- |
| AkuBrowser | `0.5.14` | `1839424a824d39ceabf1c0cf7f3aea218f1d5b65` | `v0.5.14` |
| AkuSidecar | `0.5.16` | `fd3cf7fbd24909c8ff15dd84bfd38018d482633e` | `v0.5.16` |
| AkuBridge | `0.5.29` / `aku-bridge-0.5.29-source-fidelity-v31` | `f9ea383226ef3b86b5b5ce94a7f5c9e80efe892b` | `v0.5.29` |
| AkuSupervisor | `0.1.0` | `62e3d0f276e82ca73c1009e27a468f86e151a739` | `v0.1.0` |

The AkuBrowser tag includes this release manifest and therefore advances past
the code baseline shown above. The other tags point directly at their listed
baseline commits.

Required bridge compatibility at this checkpoint:

- minimum extension version: `0.5.29`;
- runtime revision: `source-fidelity-v31`;
- X adapter: `x-dom-v12`;
- LinkedIn adapter: `linkedin-dom-v8`; and
- required cooperative action: `reload_self`.

## Acceptance evidence

### Live product path

- Unified Catch Up session `1cf6299c-6b4d-40ed-b97b-30830321913d`
  completed X and LinkedIn with six material items. Both sources restored their
  pre-run position and their configured reasoning phases completed.
- After restarting AkuSidecar and reloading AkuBridge, smoke session
  `92499f23-6901-4819-be97-1c9f98622aba` completed both sources with four
  material items. X completed Terra/high candidate evaluation; LinkedIn
  completed deterministically without another model call because its observed
  evidence was already known.
- The live UI passed Back to top, LinkedIn Brief/Source layout switching, and
  image-viewer checks. The image viewer used a `1059 x 738` stage inside a
  `1920 x 855` viewport rather than rendering the source as a thumbnail.
- No retained or newly promoted acceptance item contained a quoted video.
  Quoted-video native-post behavior therefore remained covered by the
  automated regression suite rather than a live specimen in this checkpoint.

### Lifecycle and bridge recovery

- AkuSupervisor restarted AkuSidecar successfully and reported healthy process
  and HTTP transport state with `restartCount: 1`.
- Runtime Settings remained identical across the restart. The serialized
  configuration fingerprint before and after was
  `bde2adcc2fb76adb92c7ef5e2fd39966ebfac719a47ecd8a4daa23b9437b7d75`.
- `bridge validate` request
  `acceptance-bridge-validate-20260714-1917` passed the canonical six-stage
  audit: `requested -> relay_created -> delivered -> accepted ->
  heartbeat_observed -> completed`.
- The observed post-reload build was exactly
  `aku-bridge-0.5.29-source-fidelity-v31`, with no zombie cooperative action.
- A two-browser regression proved that an AkuBrowser URL without AkuBridge
  remains passive while the compatible Chrome tab receives and completes the
  cooperative reload. This closes the relay race discovered during acceptance.
- AkuSupervisor development and stable executables were byte-identical at
  checkpoint time. Both SHA-256 values were
  `DB93B9B9431FA4EA601781B9890107AD28954D5147F5988F24685F866B8F4D06`,
  so no stable promotion was needed.

### Automated verification

- AkuBrowser aggregate `npm run check`: passed.
- AkuBrowser cross-repository contract synchronization: passed.
- AkuSidecar: 98 tests passed, zero failures.
- AkuBridge package verification: passed without writing an artifact;
  fingerprint
  `6d36f92173284467e3c4ce4468488965e6856801995db75261e0ec0b36187a39`.
- AkuSupervisor `cargo test --all-targets --all-features`: passed using the
  complete project-local Rust toolchain and an isolated build target.
- Tracked relative Markdown links and `git diff --check`: passed.

## Known non-blockers

- X rolling health is `degraded` at `4/5` because the first acceptance attempt
  opened a completely cold X tab while Chrome was controlled in the
  background. The next two X runs completed, the latest status is `completed`,
  there are no consecutive failures, and restoration failures remain zero.
  The historical failure should leave the five-run window through ordinary
  successful use; no synthetic run is required.
- LinkedIn rolling health is healthy at `5/5`.
- Source coverage remains bounded and partial by product contract. This release
  does not claim full-feed coverage.

## Preference-model boundary

> Historical checkpoint note: this shadow-only boundary was superseded later
> on July 14 by Preference Runtime v1. The figures below describe release state
> at checkpoint time, not current product behavior.

Live preference influence remains disabled. At checkpoint time the offline
experiment was `blocked` and had passed two of five readiness gates:

| Gate | Observed | Required | Status |
| --- | ---: | ---: | --- |
| Feedback events | 19 | 30 | Collecting |
| More like this | 11 | 15 | Collecting |
| Less like this | 8 | 5 | Passed |
| Assessed feedback | 19 | 20 | Collecting |
| Feedback runs | 12 | 10 | Passed |

The next product phase is normal-use feedback collection. Do not manufacture
synthetic feedback to clear the gates. Fit a new offline snapshot and inspect
its shadow comparison only after all five readiness gates pass; live influence
requires a separate activation decision.

## Release exclusions

This checkpoint does not:

- enable live preference ranking or exploration;
- migrate AkuSidecar to another language or packaging phase;
- add browser write authority, posting, messaging, liking, or following;
- reset or delete the pilot database; or
- claim production-grade consumer distribution.
