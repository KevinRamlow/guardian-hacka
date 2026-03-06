# Zendesk Skill Setup

## Quick Start (Mock Mode)

The skill works out-of-the-box in **mock mode** for testing and demonstration:

```bash
cd /root/.openclaw/workspace/skills/zendesk
./scripts/zendesk.sh status
```

All commands will show `[MOCK DATA]` when running without credentials.

## Production Setup

### 1. Get Zendesk API Credentials

**Generate API Token:**
1. Log in to Zendesk Admin Center
2. Go to **Apps and integrations** > **APIs** > **Zendesk API**
3. Under **Settings**, click **Add API token**
4. Enter a description (e.g., "Billy Integration")
5. Click **Create**
6. **Copy the token immediately** — you won't see it again!

**Your subdomain:**
- If your Zendesk URL is `https://brandlovrs.zendesk.com`, your subdomain is `brandlovrs`

### 2. Configure Environment Variables

Create `/root/.openclaw/workspace/.env.zendesk`:

```bash
export ZENDESK_SUBDOMAIN="your-subdomain"
export ZENDESK_EMAIL="your-email@company.com"
export ZENDESK_API_TOKEN="your-api-token-here"
```

**Security:**
```bash
chmod 600 /root/.openclaw/workspace/.env.zendesk
```

### 3. Load Credentials

Add to Billy's shell config or gateway environment:

```bash
source /root/.openclaw/workspace/.env.zendesk
```

### 4. Test Real API Connection

```bash
./scripts/zendesk.sh status
```

If configured correctly, you'll see real data **without** the `[MOCK DATA]` indicator.

## Troubleshooting

### Authentication Errors

**"Authentication failed"**
- Verify subdomain is correct (no `https://` or `.zendesk.com`)
- Check email matches your Zendesk login
- Regenerate API token if expired

### No Data

**"No tickets found"**
- Try expanding time range: `--days 90`
- Verify your API user has permission to view tickets
- Check Zendesk admin console for ticket visibility settings

### Rate Limits

**"Rate limit exceeded"**
- Zendesk limits: 700 req/min (Enterprise), 200 req/min (Pro)
- Wait 60 seconds and retry
- Reduce query frequency

## Usage Examples

### Daily Standup
```bash
./scripts/zendesk.sh status --days 1
./scripts/zendesk.sh sla
```

### Weekly Review
```bash
./scripts/zendesk.sh workload --days 7
./scripts/zendesk.sh categories
```

### Performance Monitoring
```bash
./scripts/zendesk.sh response-time --days 7
./scripts/zendesk.sh tags
```

## API Permissions Required

The API token needs:
- ✅ Read access to tickets
- ✅ Read access to users (for agent workload)
- ✅ Read access to groups (for categories)
- ✅ Read access to SLA policies
- ❌ No write permissions needed (read-only skill)

## Data Privacy

- Only aggregate metrics exposed
- No customer PII (names, emails) in outputs
- Agent names visible to team members only
- API token stored securely in environment variables

## Next Steps

Once configured:
1. Test all commands in production
2. Update Billy's TOOLS.md with Zendesk commands
3. Add to Billy's regular check-ins for CS team
4. Monitor API usage to stay within rate limits

## Support

For questions or issues:
- Check [Zendesk API Docs](https://developer.zendesk.com/api-reference/)
- Review skill logs for error details
- Contact Anton for skill updates
