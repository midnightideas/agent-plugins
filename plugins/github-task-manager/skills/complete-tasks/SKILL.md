---
name: complete-tasks
description: Manage and complete tasks tracked in GitHub issues for the current repository. Use this skill whenever the user asks you to complete outstanding GitHub issues, create new issues, or provide updates on issue progress. This skill is the primary interface for task delegation — any request involving GitHub issues in the current repository should trigger this skill. Make sure to use this skill proactively when the user mentions completing issues, checking progress, or working on tracked tasks.
---

# GitHub Task Manager

This skill manages task delegation via GitHub issues in the repository where the session is running.

## Invocation

This skill is triggered by requests like:
- "Please complete all issues assigned to you in this repo"
- "Work on your assigned issues"
- "Check and complete issues assigned to me"

## Repository Resolution

Every invocation, re-derive the repository from the local git remote:
```bash
git remote -v
```
Parse the HTTPS URL to extract `owner/repo`. The local git config is the source of truth — do not hardcode or assume a fixed repository.

## Authentication

Use the GitHub CLI (`gh`). Verify authentication:
```bash
gh auth status
```

If `gh` is not authenticated, stop and inform the user: "I don't have access to GitHub. Please ensure `gh` is authenticated with `gh auth login`."

## Identifying the Current User

Determine the username of the authenticated user:
```bash
gh api user --jq .login
```

## Label Setup

Before any other GitHub operations, ensure the `needs-input` label exists:
```bash
gh label view needs-input --repo "$OWNER/$REPO" 2>/dev/null || gh label create needs-input --repo "$OWNER/$REPO" --color "#FFA500" --description "Issue is blocked and needs user input to proceed"
```

If the label already exists this is a no-op. Do this first — every subsequent operation depends on this label being present.

## Cleanup Pass

Before processing issues, check for orphaned `needs-input` labels on closed issues and remove them:
```bash
gh issue list --state closed --label needs-input --repo "$OWNER/$REPO" --json number,title
```

For each closed issue with `needs-input`, remove the label:
```bash
gh issue edit $NUMBER --remove-label needs-input --repo "$OWNER/$REPO"
```

This is a maintenance task — don't announce it unless you find and fix something.

## Fetching Assigned Issues

Fetch only issues assigned to the current user that are **open** and do not have the `needs-input` label:
```bash
gh issue list --assignee "@me" --state open --repo "$OWNER/$REPO" --json number,title,labels,body,assignees
```

Filter locally to exclude issues with `needs-input` label.

## Issue Triage

For each assigned issue, determine:
- **Actionable (Simple)**: You have enough context and the issue is straightforward. Proceed directly.
- **Actionable (Complex)**: The issue requires significant work or multiple steps. Make a plan first, then work through it.
- **Blocked**: Needs user input or clarification. Label it `needs-input` and skip. Add a comment explaining what's needed.

### Labeling Blocked Issues

```bash
gh issue edit $NUMBER --add-label needs-input --repo "$OWNER/$REPO"
gh issue comment $NUMBER --body "I'm blocked on this issue and need your input: [explain what information or decision is needed]" --repo "$OWNER/$REPO"
```

## Processing Simple Issues

For issues you can resolve directly:
1. Add a comment: "I'm working on this issue now."
2. Create a worktree for this issue (see below)
3. Make the necessary changes in the worktree
4. Push the branch and create a PR
5. Add a comment summarizing what was done with a link to the PR
6. Remove `needs-input` label if present

## Making Changes: Worktree and PR Workflow

**Never commit directly to `main` or make changes in the session's working directory.** Always use a dedicated worktree and PR workflow:

### Step 0: Derive Main Working Directory

Before running any git commands, derive the path to the main working directory (the one with the real `.git` folder):
```bash
git fetch origin main
MAIN_TREE=$(git worktree list --porcelain | grep -m1 "^worktree " | sed 's/^worktree //')
# Namespace worktrees by the origin URL so multiple repos with overlapping issue
# numbers don't collide under /tmp. `git hash-object --stdin` gives a deterministic
# 40-char SHA-1 of any string without needing extra tools (sha256sum, etc.).
WT_PREFIX=$(git ls-remote --get-url origin | git hash-object --stdin | cut -c1-8)
WT_PATH="/tmp/${WT_PREFIX}-complete-tasks-issue-$NUMBER"
```

From the main tree, you can run `git worktree list` to see all worktrees and perform operations. All worktree paths in subsequent steps are derived from `$WT_PATH`.

### Step 0a: Read Implementation Notes Context

Before triaging issues, check `IMPLEMENTATION_NOTES.md` at the repo root for prior reasoning. This file (created and maintained by the skill) records hard decisions made in previous tasks so subsequent runs don't have to rediscover them.

```bash
NOTES_FILE="$MAIN_TREE/IMPLEMENTATION_NOTES.md"
if [ -f "$NOTES_FILE" ]; then
  echo "=== IMPLEMENTATION_NOTES.md (last 14 days) ==="
  # Two lookback windows:
  #   - <= 7 days old: full text shown
  #   - 7-14 days old: only header + first line of body (the "key point") shown
  #   - > 14 days old: omitted entirely
  # The writer should keep entries concise; this read filter is a safety net,
  # not a substitute for writing discipline.
  NOW_EPOCH=$(date -u +%s)
  WEEK_EPOCH=$((NOW_EPOCH - 7 * 86400))
  CUTOFF_EPOCH=$((NOW_EPOCH - 14 * 86400))
  awk -v week="$WEEK_EPOCH" -v cutoff="$CUTOFF_EPOCH" '
    BEGIN { entry=""; body=""; date=""; in_entry=0 }
    /^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
      if (in_entry && date != "") {
        d_str = date; gsub("-", " ", d_str)
        d = mktime(d_str " 00 00 00")
        if (d >= cutoff) {
          if (d >= week) {
            print entry body "\n"
          } else {
            # Compressed: header + first content line of body only
            key = body
            sub(/^\n+/, "", key)        # strip leading newlines
            sub(/\n.*$/, "", key)        # keep only the first line
            print entry "(summary) " key "\n"
          }
        }
      }
      date = substr($0, 4, 10)
      entry = $0 "\n"; body = ""; in_entry = 1; next
    }
    in_entry { body = body $0 "\n" }
    END { if (in_entry && date != "") {
      d_str = date; gsub("-", " ", d_str)
      d = mktime(d_str " 00 00 00")
      if (d >= cutoff) {
        if (d >= week) {
          print entry body "\n"
        } else {
          key = body
          sub(/^\n+/, "", key)
          sub(/\n.*$/, "", key)
          print entry "(summary) " key "\n"
        }
      }
    } }
  ' "$NOTES_FILE"
  echo "=== END ==="
else
  echo "No IMPLEMENTATION_NOTES.md yet — this is the first run."
fi
```

Entries within the last 7 days are shown in full. Entries 7-14 days old are compressed to their header + the first content line (the "key point"). Entries older than 14 days are omitted. The file on disk keeps the full historical text — only the read filter is lossy. If the file grows unreasonably large, the user can manually compress or archive old sections; the skill does not do destructive edits to the file.

Use any patterns, prior decisions, or "gotchas" surfaced here to inform the current task. If you change your approach because of a prior note, briefly comment on it in the Step 7 entry for this task so the reasoning chain is preserved.

### Step 0b: Check for Existing PR

Before creating a new worktree, always check if a PR already exists for this issue to avoid duplicates. Match by **head-branch name** (the `issue/$NUMBER-*` pattern) — title substrings false-match (e.g. `#12` inside `#123`):

Several races can produce duplicate branches/PRs:
- A parallel run just created the PR but the local `gh` cache hasn't refreshed.
- A branch was pushed locally but the PR hasn't been created yet.
- A PR was just merged; its remote branch was deleted, but `gh pr list --state all` still returns it.

To handle these, the check has three levels (remotely-tracked PR → locally-tracked branch → fresh worktree), each with a re-check at the moment of side effect:

```bash
# Refresh remote refs so a branch pushed by a parallel run is visible locally.
# Constrain to matching refs to keep the fetch cheap and predictable. The `+`
# prefix is required for git to interpret the `*` as a refspec wildcard.
git fetch origin "+refs/heads/issue/${NUMBER}-*:refs/remotes/origin/issue/${NUMBER}-*" 2>/dev/null || true

# Match by head-ref pattern: issue/$NUMBER-*. Filter to OPEN PRs — a MERGED or
# CLOSED PR is not something to "reuse"; the work is already done (merged) or
# rejected (closed).
EXISTING_PR=$(gh pr list --repo "$OWNER/$REPO" --state open --json number,headRefName \
  --jq "[.[] | select(.headRefName | startswith(\"issue/$NUMBER-\"))] | .[0] // empty")
if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
  PR_NUMBER=$(echo "$EXISTING_PR" | jq -r '.number')
  PR_BRANCH=$(echo "$EXISTING_PR" | jq -r '.headRefName')
  echo "Found existing PR #$PR_NUMBER ($PR_BRANCH)"
  # Re-check the PR is still open: a parallel run may have merged/closed it
  # between the list call above and the worktree work below.
  if [ "$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json state --jq .state)" != "OPEN" ]; then
    echo "PR #$PR_NUMBER is no longer open — skipping this issue (treat as done)."
    exit 0
  fi
  # Check if the branch is already attached as a worktree
  if git worktree list | grep -q "$WT_PATH"; then
    # Verify the worktree is clean before reusing — refuse if it has uncommitted changes
    if [ -n "$(git -C "$WT_PATH" status --porcelain)" ]; then
      echo "Existing worktree for issue $NUMBER has uncommitted changes — skipping this issue"
      exit 0
    fi
    echo "Worktree already exists at $WT_PATH"
    cd "$WT_PATH"
    git checkout "$PR_BRANCH"
  elif git branch -r | grep -q "origin/$PR_BRANCH"; then
    # Branch exists remotely but no local worktree — reuse it
    # Wrap in a re-check: a parallel run could delete the remote branch between the
    # existence check above and the worktree add below.
    echo "Reusing remote branch $PR_BRANCH"
    # Re-verify the PR before any state mutation
    if [ "$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json state --jq .state)" != "OPEN" ]; then
      echo "PR #$PR_NUMBER was closed during reuse — skipping."
      exit 0
    fi
    if ! git worktree add "$WT_PATH" "origin/$PR_BRANCH"; then
      echo "PR #$PR_NUMBER exists but branch $PR_BRANCH could not be checked out — skipping this issue"
      exit 0
    fi
    cd "$WT_PATH"
  elif git show-ref --verify --quiet "refs/heads/$PR_BRANCH"; then
    # Branch exists locally only (a parallel run pushed it and created a PR but
    # the remote ref hasn't propagated, or a prior session left it). Use it
    # rather than creating a duplicate.
    echo "Reusing local-only branch $PR_BRANCH"
    if [ "$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json state --jq .state)" != "OPEN" ]; then
      echo "PR #$PR_NUMBER was closed during reuse — skipping."
      exit 0
    fi
    if ! git worktree add "$WT_PATH" "$PR_BRANCH"; then
      echo "PR #$PR_NUMBER exists but local branch $PR_BRANCH could not be checked out — skipping this issue"
      exit 0
    fi
    cd "$WT_PATH"
  else
    # PR exists but no branch is visible anywhere — likely just-pushed by a
    # parallel run that we haven't observed yet. Re-check more aggressively
    # before declaring the branch gone.
    sleep 2
    git fetch origin "+refs/heads/issue/${NUMBER}-*:refs/remotes/origin/issue/${NUMBER}-*" 2>/dev/null || true
    if git branch -r | grep -q "origin/$PR_BRANCH"; then
      echo "Reusing remote branch $PR_BRANCH (after re-fetch)"
      if ! git worktree add "$WT_PATH" "origin/$PR_BRANCH"; then
        echo "PR #$PR_NUMBER exists but branch $PR_BRANCH could not be checked out — skipping this issue"
        exit 0
      fi
      cd "$WT_PATH"
    else
      echo "PR #$PR_NUMBER exists but branch $PR_BRANCH is gone — skipping this issue"
      exit 0
    fi
  fi
  # Skip to Step 2 with existing branch
else
  echo "No existing PR found — proceeding to create worktree"
fi
```

If a PR was found and reused, skip the worktree creation and go directly to Step 2 (Make Changes).

### Step 1: Create a Worktree

Create a new worktree with a dedicated branch for the issue:
```bash
cd "$MAIN_TREE"
git worktree add "$WT_PATH" origin/main
cd "$WT_PATH"
git checkout -b issue/$NUMBER-$short-description
```

Worktrees are created under `$WT_PATH` (typically `/tmp/<8-char-origin-hash>-complete-tasks-issue-$NUMBER`) — using `/tmp` avoids a bug where `git worktree add .git/worktrees/...` creates worktrees with internal `.git` files when run from inside a worktree session. The origin-hash prefix prevents collisions when multiple agents work on different repos that happen to share issue numbers.

### Step 2: Make Changes

Make all necessary code changes in the worktree directory.

### Step 3: Commit and Push

```bash
git add -A
# Author and committer identity come from the environment. Set both
# GIT_AUTHOR_* and GIT_COMMITTER_* so commits are attributed consistently
# (without GIT_COMMITTER_*, git falls back to the system gitconfig, which
# may have a different identity such as a machine's default user).
if [ -z "$GIT_AUTHOR_NAME" ] || [ -z "$GIT_AUTHOR_EMAIL" ] ||
   [ -z "$GIT_COMMITTER_NAME" ] || [ -z "$GIT_COMMITTER_EMAIL" ]; then
  echo "GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, and GIT_COMMITTER_EMAIL"
  echo "must all be set before committing. Aborting."
  exit 1
fi

git commit -m "Fix: $TITLE

Closes #$NUMBER

Co-Authored-By: Claude <noreply@anthropic.com>"

# Rebase onto latest main to avoid merge conflicts from other merged PRs
git fetch origin main
git rebase origin/main
# If there are merge conflicts: resolve them, then:
# git rebase --continue
# If you need to abandon the rebase entirely: git rebase --abort
# If the worktree is left in a rebasing state from a prior failure, run `git rebase --abort` before retrying.

# Final guard: re-check that no parallel run opened a competing PR on the
# same branch name. If one appeared, switch to reusing it instead of pushing
# our duplicate branch.
git fetch origin "+refs/heads/issue/${NUMBER}-*:refs/remotes/origin/issue/${NUMBER}-*" 2>/dev/null || true
COMPETING=$(gh pr list --repo "$OWNER/$REPO" --state open --json number,headRefName \
  --jq "[.[] | select(.headRefName == \"issue/$NUMBER-$short-description\")] | .[0] // empty")
if [ -n "$COMPETING" ] && [ "$COMPETING" != "null" ]; then
  COMPETING_PR=$(echo "$COMPETING" | jq -r '.number')
  # If this is the same PR we already detected earlier (e.g. we reused it via Step 0b), proceed normally.
  if [ -n "$PR_NUMBER" ] && [ "$COMPETING_PR" = "$PR_NUMBER" ]; then
    : # fall through to push
  else
    echo "Parallel run opened PR #$COMPETING_PR on the same branch — switching to reuse it."
    gh issue comment $NUMBER --body "A parallel run opened PR #$COMPETING_PR for this issue; reusing that branch instead of pushing a duplicate. See https://github.com/$OWNER/$REPO/pull/$COMPETING_PR" --repo "$OWNER/$REPO"
    gh issue edit $NUMBER --add-label needs-input --repo "$OWNER/$REPO"
    exit 0
  fi
fi

# Push with force-with-lease (safer than --force)
git push --force-with-lease origin issue/$NUMBER-$short-description
```

### Step 4: Create PR

```bash
# Check whether a parallel run already created the PR between our push above
# and now. If so, reuse it instead of attempting a duplicate create.
EXISTING_NOW=$(gh pr list --repo "$OWNER/$REPO" --state open --json number,headRefName \
  --jq "[.[] | select(.headRefName == \"issue/$NUMBER-$short-description\")] | .[0] // empty")
if [ -n "$EXISTING_NOW" ] && [ "$EXISTING_NOW" != "null" ]; then
  PR_NUMBER=$(echo "$EXISTING_NOW" | jq -r '.number')
  PR_URL="https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"
  echo "PR #$PR_NUMBER was already created by a parallel run — reusing it."
else
  PR_URL=$(gh pr create --repo "$OWNER/$REPO" --title "$TITLE" --body "Fixes #$NUMBER

## Summary
[describe what was done]

## Testing
[describe how changes were tested]

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)")
fi
```

### Step 5: Update Issue

Add a comment to the issue with the PR link so the reporter can review and merge. Apply `needs-input` here: even though the PR exists, the work still requires the reporter to review and approve before the issue can move forward, so it is technically blocked on user input. The cleanup pass will strip the label once the issue is closed:
```bash
gh issue comment $NUMBER --body "I've created a PR for this issue: $PR_URL" --repo "$OWNER/$REPO"
gh issue edit $NUMBER --add-label needs-input --repo "$OWNER/$REPO"
```

### Step 6: Address PR Review Feedback

When a reviewer requests changes, the feedback can come in two forms — and both must be checked and addressed:

1. **Whole-PR review comments** — the top-level body of a submitted review (`CHANGES_REQUESTED`, `COMMENTED`, or `APPROVED` state).
2. **Inline file comments** — review comments attached to a specific file and line.

Both can exist in the same review. Checking only one and missing the other is a common cause of "you didn't address my feedback" follow-ups.

#### Step 6a: Fetch all review feedback

```bash
# Submitter name and PR number from earlier steps
PR_NUMBER=...  # from Step 4

# Whole-PR review comments: each review's body, state, and submitter
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --jq '.[] | {user: .user.login, state: .state, body: .body, id: .id}'

# Inline file comments: each line-anchored review comment
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
  --jq '.[] | {path: .path, line: .line, body: .body, user: .user.login, id: .id}'

# Conversation comments (non-review issue-style comments on the PR)
gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
  --jq '.[] | {user: .user.login, body: .body, id: .id}'
```

Collect all three lists. The PR is "clean" only when all three are empty of actionable items (i.e. no `CHANGES_REQUESTED` review, no unresolved inline comments, no open conversation comments).

Note: `gh pr view --comments` shows whole-PR and conversation comments but **not** inline review comments. The `gh api` calls above are required to get the full picture.

#### Step 6b: Summarize and plan

For each piece of feedback, write down:
- **Source** (which review / which file/line)
- **What is being asked** (the actual change requested)
- **Whether it applies to this skill's scope** (some feedback is a project-level scope decision that needs human input — see Step 6d)

If the same point is raised both as a whole-PR comment and as an inline comment, list it once with both pointers — don't double-count.

#### Step 6c: Apply the changes

For each actionable item, make the change in the worktree, then commit and push. One commit per logical change is usually right; if multiple comments are minor (typos, wording), batch them into a single `Address review feedback` commit.

```bash
# Verify GIT_COMMITTER_* are set (GIT_AUTHOR_* should already be set from Step 3)
if [ -z "$GIT_COMMITTER_NAME" ] || [ -z "$GIT_COMMITTER_EMAIL" ]; then
  echo "GIT_COMMITTER_NAME and GIT_COMMITTER_EMAIL must be set before committing. Aborting."
  exit 1
fi

git add -A
git commit -m "Address PR review feedback

$REVIEWER on PR #$PR_NUMBER:
- [list each change with its source — whole-PR or file:line]

Co-Authored-By: Claude <noreply@anthropic.com>"

git push --force-with-lease origin issue/$NUMBER-$short-description
```

After pushing, re-request review:
```bash
gh pr ready "$PR_NUMBER" --repo "$OWNER/$REPO"  # in case it was marked draft
```

#### Step 6d: When feedback is out of scope

If a reviewer asks for a project-level decision (rename the repo, change release policy, choose a different framework), do not silently apply it. Comment on the PR explaining the scope boundary, then add `needs-input` to the issue and stop. The user is the only one who can make that call.

#### Step 6e: Repeat until clean

Reviews can stack: addressing one round of feedback may prompt another. Loop back to Step 6a after each push. Stop when there are no `CHANGES_REQUESTED` reviews and no open inline or conversation comments. Once clean, report the final state in the summary.

### Step 7: Append Hard Decisions to IMPLEMENTATION_NOTES.md

After the PR is created (and review feedback is clean), capture any non-obvious decisions made during this task in `IMPLEMENTATION_NOTES.md` at the repo root. This is the project-wide log the skill reads in Step 0a of subsequent runs.

**What to write** — only decisions that would cost the next run time to rediscover:
- Choosing between approaches where the alternatives were viable ("used X instead of Y because Z").
- Skipping a step with rationale ("rebase skipped because branch already up to date").
- Inferring intent from a sparse issue body ("treated the request as X because Y was ambiguous").
- Leaving a TODO or known limitation that another contributor should know about.
- Reversing a Step 0a prior decision (so the next run sees the correction).

**What NOT to write** — routine facts that are already in the diff, PR description, or commit message:
- File names changed.
- The fact that a PR was created (visible in `git log`).
- Mechanical steps the skill already documents.

**Format** — one entry per task. Each entry is a `## YYYY-MM-DD — issue #N (<short title>)` header followed by 1-3 bullet points. The LLM is free to write entries in its own style; the structure is a soft guide, not a contract. Examples:

```markdown
## 2026-07-27 — issue #31 (parallel-run PR races)
- Switched `gh pr list` from `--state all` to `--state open` so MERGED PRs don't trigger spurious 'reuse' paths.
- Added 2s sleep + re-fetch fallback to absorb push→propagation windows.
- Did not refactor into a helper function; the logic is local to Step 0b and refactoring risks regression.

## 2026-07-15 — issue #12 (auto-pull main)
- Used `git pull origin main` (not `git pull --rebase`) because the sandboxed environment lacks safe.git config and conflicts would otherwise surface as merge commits.
- Logged the reasoning here so the next run doesn't "fix" it back to rebase.
```

**Submission policy** — the file is committed in the PR that adds entries to it. If two PRs touch it at the same time, the second PR's rebase onto main resolves the conflict (entries are append-only with date-stamped headers, so conflict markers are unambiguous).

```bash
NOTES_FILE="$WT_PATH/IMPLEMENTATION_NOTES.md"
# Always write inside the worktree so the entry lands on the PR branch.
# If the file doesn't exist yet, create it with a one-line header.
if [ ! -f "$NOTES_FILE" ]; then
  cat > "$NOTES_FILE" <<'HEADER'
# Implementation Notes

Hard decisions made by the `complete-tasks` skill. Read by Step 0a of subsequent runs (last 14 days). Older entries are kept in the file but omitted from the read filter.

HEADER
fi

# Compose the entry. DATE is from `date -u +%Y-%m-%d`; ONLY append entries
# that satisfy the "what to write" criteria above — keep this empty if the
# task was a routine fix with no non-obvious decisions.
DATE=$(date -u +%Y-%m-%d)
cat >> "$NOTES_FILE" <<ENTRY

## $DATE - issue #$NUMBER ($TITLE)
<DRAFT THE BULLET POINTS HERE>

ENTRY
```

After appending, commit on the PR branch and push. The PR description already covers the high-level "what changed"; this commit's message is the natural place to summarize the entries:

```bash
cd "$WT_PATH"
git add IMPLEMENTATION_NOTES.md
git commit -m "docs: append implementation notes for issue #$NUMBER

$HUMAN_READABLE_SUMMARY_OF_DECISIONS

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to the same PR branch. force-with-lease is safe because the only
# commits on this branch since origin are local.
git push --force-with-lease origin issue/$NUMBER-$short-description
```

If no decisions qualify for the notes file (purely routine fix), skip the commit and move on — don't force an entry.

### Cleanup Worktrees

After creating the PR, you can remove the worktree. First make sure the session isn't inside the worktree being removed (otherwise `git worktree remove` will fail or leave the session in an invalid state):
```bash
cd "$MAIN_TREE"
git worktree remove "$WT_PATH"
```

**Note:** Worktrees created by this skill are stored under `/tmp/<origin-hash>-complete-tasks-issue-*`.

## Stale Worktree Cleanup

Periodically check for stale worktrees — branches whose remote counterpart no longer exists or whose PR was merged and closed:
```bash
git fetch --prune origin
git worktree list
```

For each worktree matching `${WT_PREFIX}-complete-tasks-issue-*` (same origin hash) whose branch has been merged and deleted from remote, cd back to the main tree first (to avoid removing a worktree you're inside) and then remove:
```bash
cd "$MAIN_TREE"
git worktree remove "$WT_PATH" --force
```

Use `--force` if the worktree directory has untracked files from a previous session.

## Processing Complex Issues

For issues requiring a plan:
1. Add a comment: "I'm analyzing this issue and will provide a plan shortly."
2. Create a plan for addressing the issue
3. Present the plan as a comment on the issue for the reporter to review
4. Wait for their feedback or approval before proceeding
5. If they approve, execute the plan and report back

If the reporter doesn't respond or the issue needs their input to proceed:
1. Label the issue `needs-input`
2. Comment explaining what's needed
3. Skip and move to the next issue

## Never Close Issues

**Never close issues.** The user remains solely responsible for closing. Your job is to propose solutions, provide updates, and advance work.

## Progress Tracking

When you start work on an issue, add a comment:
```
I'm looking into this issue and will provide an update shortly.
```

When you have a solution or finding, add a comment with your proposed approach. If the work is complex, periodically update with progress comments so the user can see what you've tried.

## API Rate Limits

The `gh` CLI handles rate limits automatically. If you encounter errors:
- Wait and retry for transient issues
- Report persistent failures to the user

## Workflow for "Complete all issues assigned to you"

0. **Verify session is on `main`** — this skill expects to run from the main working tree on the `main` branch. If not, stop and tell the user: "Please switch to the main branch (or run from the main checkout) before invoking this skill."
   ```bash
   git rev-parse --abbrev-ref HEAD
   ```
1. **Sync main tree** — Pull the latest `main` branch into the main working tree:
   ```bash
   git fetch origin main
   git pull origin main
   ```
2. **Verify access** — Run `gh auth status` and stop if not authenticated
3. **Cleanup pass** — Remove `needs-input` from closed issues
4. **Read Implementation Notes** — Before planning, read `IMPLEMENTATION_NOTES.md` at the repo root to surface prior hard decisions. See [Step 0a: Read Implementation Notes Context](#step-0a-read-implementation-notes-context) for the exact `awk` filter (last 14 days, 7-day compression). If no notes file exists yet, skip this step silently.
5. **Fetch assigned issues** — Get open issues assigned to `@me`, excluding `needs-input`
6. **Plan the sequence** — Do not process issues in FIFO or LIFO order. Review the full set as a batch and decide the best execution order. See [Planning the Sequence](#planning-the-sequence) below.
7. **Process each issue in the planned order**:
   - Simple → take action directly
   - Complex → make plan, present to reporter, wait for input if needed
   - Blocked → label `needs-input`, comment, skip
8. **Report summary** including the planned sequence and the rationale for the chosen order

## Planning the Sequence

After fetching the assigned issues, pause before writing any code. Review the entire batch as a single unit and decide the order to execute them in. FIFO (oldest first) and LIFO (newest first) are both wrong defaults — they ignore the actual relationships between issues.

For each issue, gather at minimum:
- **Title and body** — what the work actually is
- **Scope** — single file/area vs. cross-cutting refactor
- **Dependencies** — does this issue reference other issues, branches, or PRs? Does it block or get blocked by another?
- **Open PRs** — is there already an in-flight PR for this issue? If so, prefer advancing that PR over starting new work.
- **Risk** — does it touch shared infrastructure, security-sensitive code, or release-blocking paths?
- **Complexity** — does it require a multi-step plan or expert review before code is written?

Then choose an order. Heuristics, in order of priority:

1. **Pick up where another PR left off** — if an existing PR for an issue already has reviewer feedback, address that first. Stale PRs are the highest-priority in-flight work.
2. **Unblock others first** — if issue A blocks issue B, do A first (and surface the dependency in the plan).
3. **Foundational before dependent** — refactors or shared infrastructure changes that other issues rely on go before the consumers.
4. **Small, low-risk wins first** — fast, isolated, well-understood issues can be resolved quickly and reduce noise. Use this to chip away at the queue when nothing else dictates order.
5. **High-risk last** — changes that touch many files or carry merge-conflict risk should run after the smaller ones, so rebase interaction is minimized.
6. **Group by area** — issues that touch the same module or file are best done together, so the second one benefits from the first's worktree state and the diff stays coherent.

State the planned sequence with one-line reasoning per issue **before** you start any work. Example:

```
Planned sequence:
1. #14 (PR has reviewer feedback — address first)
2. #11 (foundational, unblocks #12)
3. #9 (small, isolated)
4. #8 (touching the same area as #9, do together)
5. #5 (cross-cutting, run last to minimize rebase churn)
```

The order is a plan, not a contract. If partway through you discover an issue is more complex than it looked, or a dependency resolves itself, re-plan the remainder and note the change in the final summary.

## Summary Output Format

After completing (or partially completing) issues, report:

```
## GitHub Task Summary

User: @username
Repository: owner/repo

Cleanup: removed needs-input from N closed issue(s) (if any)

Planned sequence (and rationale):
1. #14 — PR has reviewer feedback, address first
2. #11 — foundational, unblocks #12
3. #9 — small, isolated

Processed N issue(s):

| # | Title | Status | Notes |
|---|-------|--------|-------|
| 1 | Issue title | Done / Blocked / Plan Pending | Notes |

Issues needing your input: [list with links]
Issues advanced but not closed: [list with links]
```

If the order changed mid-run, call that out explicitly.
