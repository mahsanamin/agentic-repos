# Classifier, PR-INTRODUCED / PR-EXPOSED / PRE-EXISTING

Mandatory step before a finding is added to the draft. Silently flagging pre-existing issues as if the PR caused them is the #1 cause of low-confidence noise. This file describes the full procedure.

## The three classes

- **PR-INTRODUCED**, the issue exists because of this PR's changes. The diff added or modified the offending code.
- **PR-EXPOSED**, the PR makes a latent bug reachable. The PR didn't change the buggy code itself, but added a new caller / new code path that now exercises it.
- **PRE-EXISTING**, the same issue is present in unchanged sibling code. This PR neither introduces nor exposes it. The PR is at most a "good moment" to fix it, not the cause.

## Procedure

For each potential issue you've identified, before drafting a comment:

1. **Name the relevant symbol**, the function, variable, pattern, or filename the issue centers on. Be specific. "The validation logic" is not specific enough; `OrderItemValidator.validateItem` is.

2. **Did THIS PR introduce or modify the offending lines?**

   ```bash
   git -C "$WORKTREE_DIR" log -p --first-parent \
     -S "<symbol>" \
     "origin/$BASE_BRANCH...HEAD"
   ```

   - If the diff added or modified those exact lines: **PR-INTRODUCED**. Done.
   - If no hit (the symbol existed before, untouched by this PR): go to step 3.

3. **Does the same pattern appear in unchanged sibling files?**

   List the files the PR touched:
   ```bash
   touched=$(git -C "$WORKTREE_DIR" diff --name-only "origin/$BASE_BRANCH...HEAD")
   ```

   Grep for the pattern in everything EXCEPT those files:
   ```bash
   git -C "$WORKTREE_DIR" grep -n "<pattern>" -- \
     $(printf ':!%s ' $touched)
   ```

   - If matches appear in unchanged code: **PRE-EXISTING**. The PR didn't cause this; it's a pre-existing condition.
   - If no matches in unchanged code, AND step 2 didn't tag PR-INTRODUCED: check whether the PR added a new caller/path that now reaches the buggy code (a new `controller` method that calls an existing `service` method, etc.). If yes: **PR-EXPOSED**.

4. **Record classification** alongside the finding before drafting any comment text. Comments without classification are rejected from the draft.

## How classification affects the comment

| Class | Comment phrasing | Where to post |
|---|---|---|
| PR-INTRODUCED | "X is wrong / missing / unsafe. Suggested fix: …" | Inline on the changed line |
| PR-EXPOSED | "This PR newly exercises code path X, which has issue Y. Worth handling before this lands." | Inline on the new call site |
| PRE-EXISTING | "Optional: same pattern at file:line and N other locations. This PR is a good moment to fix the family, not just here." | "Notes" section of the draft (NOT inline). Do not phrase as if the PR caused it. |

## Edge case, refactor PRs

A refactor that moves code without changing it: a "PRE-EXISTING" classification still applies to the issue itself, but the refactor is a legitimately good moment to fix it. Mention this in the draft Notes; let the human decide whether to scope-creep the PR or file a follow-up.

## Skip the classifier when

Only one case: the PR is a pure delete (removes a file or function entirely). There's no "exists in sibling code" check needed, the PR removed the code; any reachability concerns are about callers of the now-deleted symbol.
