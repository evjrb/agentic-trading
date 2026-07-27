# robinhood-trading

Workspace for driving the Robinhood trading MCP server from Claude Code.

## MCP server

Configured in [`.mcp.json`](.mcp.json) at project scope:

| Server | Transport | URL |
| --- | --- | --- |
| `robinhood-trading` | HTTP | `https://agent.robinhood.com/mcp/trading` |

### Authenticating

The server shows **Needs authentication** until you complete OAuth:

1. Run `claude` from inside this directory.
2. Approve the project-scoped MCP server when prompted.
3. Run `/mcp` and pick `robinhood-trading` → **Authenticate** to do the Robinhood OAuth flow in your browser.

Verify status any time with `claude mcp list`.

## Safety

This is a **live brokerage** integration — orders and transfers are real money and
hard to reverse. Confirm every buy / sell / transfer explicitly before executing.
Treat read-only calls (positions, quotes, history) as safe; treat anything that
mutates an order or moves funds as requiring a deliberate go-ahead.
