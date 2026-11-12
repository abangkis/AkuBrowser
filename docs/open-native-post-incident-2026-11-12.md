# Open native post white page investigation

Date: 2026-11-12 (Asia/Jakarta).

Status: Further investigation paused at the user's request after recording the
latest occurrence below. Resume upon another occurrence or explicit direction.
The incident is unresolved; the successful checks below do not establish a fix.

## Reported symptom

The native reader window opens and the address bar already shows the original
post URL, but the page remains white. Reloading the post in that reader makes
the content appear. This is a Reload of the remote post, not the Timeline UI.

The user could not recall the exact affected post. They recalled X and LinkedIn
as likely sources; neither source attribution nor a specific failing URL was
confirmed during this investigation.

## Successful comparison

The user manually checked one post twice without Reload. They reported that the
first opening used a new reader window and displayed normally, and that opening
the same post again also remained normal. These are user-observed results;
the agent did not independently inspect rendered content.

| Check | Local audit time (WIB) | Server request total | User-observed result |
| --- | --- | --- | --- |
| First opening | 2026-11-12 11:50:00 | 205 ms | Content displayed without Reload |
| Repeat opening | 2026-11-12 11:51:03 | 266 ms | Content displayed without Reload |

The matching audit entries completed successfully and verified reader foreground:

- First: `split_b595b4bb0b7112337a55530a5a936a7c`.
- Repeat: `split_99cc599c7cff45f49347744feade8bac`.

The timing measures the server action, not click-to-visible-content latency.
Exact tab reuse was not independently observed. Neither check reproduced the
reported white page.

## Later occurrence during a batch update

After the successful comparison, the user reported another temporarily empty
reader page. This time the content appeared after a few seconds without Reload.
The supplied screenshot shows the loaded X post at
<https://x.com/blader/status/2120649573446438916>. It shows the recovered page,
not the preceding empty state. The exact blank duration was not measured.

The latest matching-time native action was
`split_0835a729c40d868c3e4855741a9db833`, queued at
`2026-11-12T05:09:50.631796Z` (12:09:50 WIB). It completed successfully at
`2026-11-12T05:09:50.8536821Z`, with a 223 ms server request total and verified
foreground. The audit does not persist the target URL, so the temporal match
does not independently prove URL-to-action identity.

Batch `session_fa5133b1df1f480648713e7b3a543696` ran from
`2026-11-12T05:09:40.2378588Z` to `2026-11-12T05:10:27.0927844Z`
(12:09:40-12:10:27 WIB). The native action therefore overlapped a running batch.
This confirms temporal overlap, not that the batch caused the empty page.
The reader's remote document/navigation/rendering state was not captured during
the delay. Shared browser contention, network loading, and site rendering remain
unverified possibilities; no root cause or automatic Reload fix was established.

At the subsequent 12:11 WIB readback the runtime was idle, with epoch
`epoch_e721329f5f09e402d1fa1add30dad03a`. This differs from the earlier baseline;
the investigation did not restart or activate the runtime. Preserve these
observations separately rather than treating them as one uninterrupted process.

## Confirmed implementation boundaries

The inspected runtime used the ordinary Bridge route. In
[`reader-window-runtime.js`](../../AkuBridge/reader-window-runtime.js), a cold
reader starts on a local marker and then navigates to the post. An existing
reader creates a tab for a new URL; an exact-URL tab is only activated, without
Reload or a new navigation.

[`service-worker.js`](../../AkuBridge/service-worker.js) reports
`native_post_opened` after the reader operation. The successful result verifies
the window/foreground handoff, but does not establish that the remote post has
finished loading or is usable. The durable `split_action_audit` records do not
identify cold versus reused tabs or remote content readiness.

Activating a previously stalled exact-URL tab could therefore leave it stalled.
This remains a hypothesis, not a demonstrated cause of the reported incident.

One separate action at 11:38 WIB showed approximately 1.14 seconds between broker
receipt and attachment, and a 258 ms server request total. This exposed
a timing gap before queue admission; it does not explain the reported white
remote page. Earlier approximately 200 ms action measurements must not be used
as evidence of complete click-to-content latency.

## Evidence and limitations

- Earlier baseline runtime bundle: Sidecar source `4597d81e23b7b338df8366ca6087547f9140f3df`,
  built `2026-11-12T04:13:02.9122254Z`; source dirty flag was already present.
- Earlier baseline epoch: `epoch_8b3135c3c6f97e88b5133d6305b3a56e`.
- Audit: `AkuSidecar/runtime/aku-sidecar.db`, table `split_action_audit`.
- Logs: `%LOCALAPPDATA%/AkuSupervisor/.runtime/services/akusidecar.stdout.log`.
- Computer Use repeatedly failed to bind the detected AkuBrowser window with
  `window id 132898 no longer belongs to Chrome; current owner is Chrome`.
  No agent-driven click, navigation, or Reload was performed.
- At the pause checkpoint, the investigation had made no code, settings, or
  runtime changes. Publishing this note and subsequent SI tracking updates are
  separate from implementation or activation.

Roadmap reference from this chat: AkuBrowser project
`5e026b8f-dcda-26f6-d364-a71485f84b8d` in registry `si-local`, Open native post
track `e80fee82-2bfc-44e3-9347-a910aceccc11`, Stage 01
`44f98b59-0c1d-40ba-97ee-9e3a8468660f`. This local pause note does not change the
SI stage status or satisfy its exit criteria.

## Resume on the next occurrence

Record the source, exact post URL, local time, whether the reader window was new
or already open, and whether the tab was new or reused. If practical, capture
the white page and address bar before Reload, then record whether Reload restores
the content. Correlate that occurrence with the broker/action IDs and the existing
tab-local `window.akuNativePostDiagnostics.read()` trace through an available,
authorized browser inspection surface.

The unresolved question is which part of remote navigation or rendering fails
before Reload. If further diagnostics are approved, record navigation completion
and failure against the exact owned tab/post and distinguish cold/reused cases.
That instrumentation and any recovery change remain proposals, not implemented
or approved work. Resume investigation only when another occurrence is reported
or the user explicitly requests it.
