# Release pipeline — one-time setup

`modules.yml` cannot publish until the three things below exist. They are
repository and organisation settings, not code, so they are not created by
merging this file. **Until step 3 is done the approval gate is decorative**,
because anyone with push access can still create a tag by hand.

Do them in order. Steps 1 and 2 are inert on their own; step 3 is the one that
changes who can release.

## 1. GitHub App — `impel-release-bot`

The tag ruleset in step 3 blocks tag creation for everybody. Something has to
be allowed through, and `GITHUB_TOKEN` cannot be: it is not a real identity, so
it cannot appear on a ruleset bypass list. That is the only reason this App
exists.

Organisation settings → Developer settings → GitHub Apps → **New GitHub App**:

- **Name:** `impel-release-bot`
- **Homepage:** this repository's URL
- **Webhook:** uncheck *Active*
- **Repository permissions:** `Contents: Read and write` — nothing else.
  Not `Workflows: write`; the App pushes tags, never workflow files, and the
  narrower the token the less a leaked one is worth.
- **Where can this app be installed:** *Only on this account*

Then:

1. **Install** it on `impel-terraform-modules` only — *Only select repositories*.
2. Note the **Client ID** from the App's settings page.
3. **Generate a private key** and download the `.pem`.

In this repository's Settings → Secrets and variables → Actions:

| Kind | Name | Value |
|---|---|---|
| Variable | `RELEASE_APP_CLIENT_ID` | the App's Client ID |
| Secret | `RELEASE_APP_PRIVATE_KEY` | the whole `.pem`, including the BEGIN/END lines |

Delete the downloaded `.pem` afterwards. It can be regenerated; a copy sitting
in `~/Downloads` is a tag-signing credential for the estate.

> Client ID, not App ID: `create-github-app-token` v3 deprecated the `app-id`
> input in favour of `client-id`.

## 2. `release` environment

Settings → Environments → **New environment** → `release`.

- **Required reviewers:** `@UseImpel/platform-approvers`
- **Prevent self-review:** *off* — matching `aws-dev` in `impel-infra-dev`, so a
  release never waits on a second person being awake.
- **Deployment branches:** *Selected branches* → `main`

That last one is not optional. Without it a `workflow_dispatch` from any branch
reaches the gate, and an approver who is only glancing at the version number
would approve a release built from an unmerged branch. `plan-release` also
checks the commit is an ancestor of `main`, so this is the second of two locks
on the same door.

## 3. Tag ruleset

Settings → Rules → Rulesets → **New ruleset** → *New tag ruleset*.

- **Name:** `release tags`
- **Enforcement status:** *Active*
- **Target tags:** *Include by pattern* → `v*`
- **Bypass list:** `impel-release-bot` only. Not the `platform-approvers` team,
  and not repository admins — a bypass that includes the people most likely to
  be in a hurry is not a control.
- **Rules:** tick **Restrict creations**, **Restrict updates**, and
  **Restrict deletions**.

Updates and deletions matter as much as creation. A moved tag hands a consumer
different code under a version they already reviewed, which is the exact
guarantee that pinning by tag is supposed to provide.

### Verify it fails closed

From a clone, with push access:

```sh
git tag -a v9.9.9 -m test
git push origin v9.9.9     # must be REJECTED
git tag -d v9.9.9
```

If that push succeeds, the ruleset is not doing anything and neither is the
approval gate. Fix it before relying on the pipeline.

## Rotating the private key

Generate a new key on the App, update `RELEASE_APP_PRIVATE_KEY`, then delete
the old key from the App. Doing it in that order means no release is blocked
in between.

## If a release half-fails

The tag is pushed before the release is created, so a failure between the two
leaves a tag with no release. The tag is the thing consumers resolve, so the
module version is already usable — the gap is cosmetic. Create the missing
release from the existing tag:

```sh
gh release create v1.3.0 --title v1.3.0 --generate-notes
```

Do **not** delete and recreate the tag to re-run the pipeline. The ruleset
blocks it, and that is deliberate.
