# Free cloud dashboard: external scheduler + Actions + Pages

[中文（默认）](CLOUD_DEPLOY.md) | **English** · [README](../README.en.md)

## Structure

- `main`: source, layout, configuration templates, and tests.
- `runtime-data`: separate quota input branch, with `quotas.json` at its root; it does not trigger source CI.
- Pages artifacts: `screen.png`, `status.json`, and the status page, without committing generated output to source.
- Raw dashboard JSON is used during generation and is not published.

The old `gh-pages` branch remains for migration rollback; the new pipeline does not commit to it. Separate branches are still part of the same repository, with the same visibility.

## External trigger

Create a cron-job.org job:

- Name: Shawn Kanban half-hour render
- URL: `https://api.github.com/repos/shenliucn-prog/shawn-kanban/actions/workflows/render.yml/dispatches`
- Method: POST
- Body: `{"ref":"main"}`
- Schedule: minute 25 and 55 of every hour, leaving time for generation before Kindle refresh at :00 and :30. The configured job uses America/Los_Angeles; these minute positions also match UTC.
- Headers: `Accept: application/vnd.github+json`, `Content-Type: application/json`, and `Authorization: Bearer <dedicated-token>`.

Use a fine-grained GitHub token restricted to `shawn-kanban`, with Actions write permission and required Metadata read access. Set an expiry and renew it before that date. Store the credential only in the scheduler's authentication header, never in the URL or Git. Do not give the scheduler an existing account-wide token.

An accepted dispatch is not proof of a successful image deployment. The scheduler returns quickly; inspect Actions for generation and deployment results.

GitHub's :17 and :47 schedule is a backup. `cancel-in-progress: false` prevents new triggers from interrupting an active generation. External scheduling cannot guarantee immediate runner availability.

## Pages

In Settings → Pages, select GitHub Actions as the source. The workflow uses upload-pages-artifact and deploy-pages.

- Image: `https://shenliucn-prog.github.io/shawn-kanban/screen.png`
- Status page: `https://shenliucn-prog.github.io/shawn-kanban/`
- Machine status: `https://shenliucn-prog.github.io/shawn-kanban/status.json`

Each run reads the previous image and checksum. If all public providers fail, fonts are unavailable, or rendering fails, it retains the last good image and publishes failure status where possible. An earlier failure, such as dependency installation, produces no deployment and leaves existing Pages content intact. The status page computes age from generation time and marks images older than 45 minutes as stale.

`status.json` retains the latest 256 generation results, timestamps, run IDs, and trigger types. Exact dispatch, queue, and deployment times come from GitHub run/job metadata. Do not treat dispatch acceptance as deployment completion.

## Local reporter migration

Update the reporter and change `GITHUB_BRANCH=main` to `GITHUB_BRANCH=runtime-data` in your private configuration. The default remote path is now `quotas.json`.

Local files live under `SHAWN_DATA_DIR`, defaulting to `~/.local/share/shawn-kanban/`. Successful-upload state is separate from collection state; a failed upload remains eligible for retry. A five-minute heartbeat prevents unchanged usage from appearing offline.

Metric meanings are unchanged: the cloud reporter's Claude Code field counts WorkBuddy messages, and its Codex field counts file activity. Neither represents authoritative account quota. Do not include sensitive task text in runtime input: `runtime-data` is public, like this repository.

## 48-hour validation

Starting when the external job is enabled, check request acceptance, Actions execution, Pages deployment, and whether image age exceeds 45 minutes. Successful backup cron runs alone do not validate the external scheduler. Kindle sleep/resume requires separate device testing.
