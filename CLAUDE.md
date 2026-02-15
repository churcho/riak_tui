# Claude Code Project Instructions

## Behavioral Guidelines (ALWAYS FOLLOW)

### 1. Think Before Coding

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.

### 2. Simplicity First

- No features beyond what was asked.
- No abstractions for single-use code.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### 3. Surgical Changes

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Match existing style, even if you'd do it differently.
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

### 4. Goal-Driven Execution

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"

### 5. Fresh-Eyes Review After Implementation

After completing any non-trivial code change, re-read all modified code looking for:
- Incorrect API usage (wrong function signatures, option shapes, argument order)
- Pattern matching gaps or clauses that can never match
- Hardcoded assumptions that don't hold across environments

---

## Technology Stack

**riak_tui** is an Elixir terminal UI application for monitoring and managing Riak clusters.

- **Language**: Elixir 1.19+ on OTP 28
- **HTTP Client**: Req
- **JSON**: Jason
- **TUI**: term_ui (future — Milestone 5)
- **Testing**: ExUnit + Bypass (HTTP mocking)
- **Static Analysis**: Dialyxir, Credo
- **Never use**: Phoenix, LiveView, Ecto, npm/yarn

### Module Naming

- **Application module**: `RiakTui`
- **OTP app**: `:riak_tui`

### Key Modules

- `RiakTui.Client` — HTTP client for the Riak Admin API
- `RiakTui.DCRegistry` — GenServer tracking known DCs, manages active DC selection
- `RiakTui.ClusterPoller` — GenServer polling cluster data at intervals, notifies subscribers

### Riak Admin API

The Riak devrel cluster exposes an admin API on port pattern `100N5` (dev1=10015, dev2=10025, etc.). Default bootstrap URL: `http://127.0.0.1:10015`.

Available endpoints:
- `GET /api/ping` — health check
- `GET /api/cluster/status` — cluster membership and health
- `GET /api/dcs` — datacenter discovery
- `GET /api/ring/ownership` — partition-to-node mapping
- `GET /api/nodes/:node/stats` — per-node stats
- `GET /api/handoff/status` — handoff transfers
- `GET /api/aae/status` — AAE exchange status

## Code Style

### Documentation

- Every module gets `@moduledoc`
- Every public function gets `@doc` and `@spec`
- Never add `@doc` to private functions

### Type Specs

- `@spec` on all public functions
- Define named types for complex return values

### Logging

- Use `[riak_tui]` prefix for grep-friendly filtering
- `Logger.debug` for per-poll tracing, `Logger.info` for lifecycle, `Logger.warning` for recoverable errors, `Logger.error` for things needing attention

### Error Handling

- Public functions return `{:ok, result}` or `{:error, reason}` — never raise
- GenServers handle errors gracefully and continue running

## Testing Standards

### What to Test

- One happy path test per public function
- One error path test
- Edge cases for pattern matching on data shapes

### HTTP Mocking

Use Bypass for all HTTP tests — never hit real endpoints in tests.

### Running Tests

```bash
mix test              # Full suite
mix test path/to/test # Specific file
```

## Quality Gates

```bash
mix compile --warnings-as-errors  # Zero warnings
mix test                           # All tests pass
mix credo --strict                 # Static analysis
mix dialyzer                       # Type checking (zero warnings target)
mix format                         # Code formatting
```

## Explore Before Edit

Before editing any Elixir source file, first understand the existing code:
1. Read the target file(s) and understand their structure
2. Identify existing patterns and naming conventions
3. Check for callers and dependencies
4. Note any related tests

## Git Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <short description>
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

### Before Committing

- `mix test` — full suite passes
- `mix format` — all files formatted
- `mix credo --strict` — no issues
- Remove debug statements (`IO.inspect`, `dbg()`)
