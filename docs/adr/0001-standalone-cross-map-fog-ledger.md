# Keep cross-map fog in a standalone ledger

The fog skill maintains a repository ledger instead of changing the Wayfinder map format or storing unresolved work inside closed maps alone. Active-map fog remains owned by Wayfinder, while the ledger supplies cross-map findability, loose coupling, and standalone capture and sweep workflows; the trade-off is that integration relies on explicit routing and model invocation rather than Wayfinder calling the skill directly.
