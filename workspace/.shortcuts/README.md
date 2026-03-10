# .shortcuts - Son of Anton SSH Monitoring Helpers

These scripts monitor Anton (Mac) remotely via SSH.

## Prerequisites

1. SSH config with `anton-mac` host:
```
Host anton-mac
  HostName <mac-ip>
  User fonsecabc
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking no
```

2. Public key authorized on Mac:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3n4XbN5ifFILbai/NbimwG7U13Luku2JCn+OfeYvm8 son-of-anton@89.167.23.2
```

## Scripts

- `monitor-anton` — Full status check (auto-loop + agents + state)
- `check-agents` — Agent registry list
- `tail-logs` — Recent activity logs
- `auto-loop-status` — Auto-loop heartbeat check

All scripts assume `anton-mac` SSH host is configured.
