# Agent 22: ScriptingEngine — Memory

## Fixed Issues
- Sandbox: new() disables os/io (new_unsafe() was the bug)
- Instruction count hook prevents infinite loops
- Path traversal prevented by sandbox root
- Console history capped at 10000

## Gotchas
- new_unsafe() gives ALL libraries including os (shell execution!)
- Instruction count set BEFORE execution
- "../../../etc/passwd" must be caught by path validation
