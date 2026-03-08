# Error Handling Reference

## Error Classification

| Error | Action |
|-------|--------|
| **403 Forbidden** | You forgot to `source .env.guardian-eval`. Source it and retry. |
| **429 Rate Limit** | Wait 30s and retry. Max 3 retries, then mark `blocked`. |
| **MAX_TOKENS** | Input too long for model. Skip this item, log it, continue with others. |
| **ModuleNotFoundError** | Run `pip install <module>` in the workspace venv, then retry. |

## When Blocked

Log with this format:
```
BLOCKED: [error type] on [what you were doing]. Tried: [list attempts]. Need: [what's required to unblock].
```

Then set status to `blocked` — do not loop indefinitely.
