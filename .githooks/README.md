# Git Hooks

## Pre-commit Hook

This pre-commit hook performs automatic checks before finalizing your commit.
It is the fast half of the gate: the whole gate is in `ci.sh`, and the hook
is the part that catches a change that does not compile.

### What It Runs

The hook runs `moon check` -- the type check of every package in the project
-- before the commit is created.

### Usage Instructions

To use this pre-commit hook:

1. Make the hook executable if it isn't already:
   ```bash
   chmod +x .githooks/pre-commit
   ```

2. Configure Git to use the hooks in the .githooks directory:
   ```bash
   git config core.hooksPath .githooks
   ```

3. The hook will automatically run when you execute `git commit`
