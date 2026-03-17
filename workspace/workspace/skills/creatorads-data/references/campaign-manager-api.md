# Campaign Manager API — Database Usage

Core campaign management service. Manages campaigns, creator groups, invites, content delivery, boost ads, and payments.

**Codebase**: `/Users/fonsecabc/brandlovrs/campaigns/campaign-manager-api` (Golang, GORM)
**Database**: db-maestro-prod (MySQL)

## Key Queries

### Campaign Budget Summary
```sql
SELECT SUM(cgi.reward_value) as budgetCompromised, cgi.campaign_id as id
FROM creator_group_invites cgi
WHERE cgi.campaign_id = ?
  AND cgi.status IN ('participating', 'paid', 'paid_partial', 'pending_payment')
  AND cgi.deleted_at IS NULL
GROUP BY cgi.campaign_id
```

### Latest Creator Invite Per Campaign (dedup)
```sql
SELECT cgi1.*
FROM creator_group_invites cgi1
WHERE cgi1.id = (
  SELECT MAX(cgi2.id)
  FROM creator_group_invites cgi2
  WHERE cgi2.campaign_id = cgi1.campaign_id
    AND cgi2.creator_id = cgi1.creator_id
    AND cgi2.deleted_at IS NULL
)
AND cgi1.deleted_at IS NULL
```

### Content Count Per Moment
```sql
SELECT COUNT(1) as total, m.id as id
FROM media_content mc
INNER JOIN actions act ON act.id = mc.action_id
INNER JOIN ads a ON a.id = act.ad_id
INNER JOIN moments m ON m.id = a.moment_id
WHERE m.id IN (?)
  AND mc.deleted_at IS NULL AND act.deleted_at IS NULL AND a.deleted_at IS NULL
GROUP BY m.id
```

### Payment Totals Aggregation
```sql
SELECT subscription_id, creator_id, campaign_id,
       SUM(gross_value) AS gross_value,
       MAX(payment_status) AS payment_status,
       MAX(date_of_transaction) AS payment_date
FROM creator_payment_history
WHERE payment_status IN (?)
GROUP BY subscription_id, creator_id, campaign_id
```

### Late/Overdue Content Detection
```sql
SELECT COUNT(1)
FROM actions act
INNER JOIN ads a ON a.id = act.ad_id
INNER JOIN moments m ON m.id = a.moment_id
WHERE m.campaign_id = ?
  AND EXISTS (
    SELECT 1 FROM creator_group_invites cgi
    WHERE cgi.creator_id = act.creator_id
      AND cgi.campaign_id = m.campaign_id
      AND cgi.status = 'participating'
  )
  AND (
    EXISTS (SELECT 1 FROM media_content mc WHERE mc.action_id = act.id AND mc.created_at > m.receive_content)
    OR (act.approved_at IS NOT NULL AND act.posted_at IS NULL)
    OR (act.approved_at IS NOT NULL AND act.posted_at > m.ends_at)
  )
```

### Content Send Reminder
```sql
SELECT m.id as moment_id, m.receive_content, COUNT(cgi.creator_id) as creator_count
FROM moments m
INNER JOIN creator_group_moment cgm ON cgm.moment_id = m.id
INNER JOIN creator_groups cg ON cg.id = cgm.creator_group_id
INNER JOIN creator_group_invites cgi ON cgi.creator_group_id = cg.id AND cgi.campaign_id = ?
INNER JOIN ads a ON a.moment_id = m.id AND a.deleted_at IS NULL
INNER JOIN actions act ON act.ad_id = a.id AND act.creator_id = cgi.creator_id AND act.deleted_at IS NULL
WHERE m.campaign_id = ? AND m.receive_content IS NOT NULL
  AND m.receive_content >= CURRENT_TIMESTAMP
  AND m.deleted_at IS NULL AND cg.deleted_at IS NULL
  AND cgi.deleted_at IS NULL AND cgi.status = 'participating'
  AND cgi.approved_at IS NOT NULL AND act.approved_at IS NULL
GROUP BY m.id, m.receive_content
```

## Tables Managed (42 total)

**Campaign CRUD**: campaigns, campaign_states, moments, moments_custom_attributes, secondary_hashtags_moments
**Ads**: ads, formats, format_sources, format_reference_types, format_attributes, ads_attributes
**Creator Groups**: creator_groups, creator_group_rewards, creator_group_moment, reward_types, group_discarded_creators
**Invites**: creator_group_invites, creator_group_invites_additional_infos, creator_group_invite_sm_positions
**Content**: actions, media_content
**Moderation (read-only)**: proofread_medias, proofread_guidelines, proofread_medias_songs_audit, guidelines
**Coupons**: coupon_settings, creator_coupons
**Payments**: creator_payment_history, brand_fee_settings
**Boost**: boost_ads, boost_facebook_business_oauth, boost_partnership_authorizations, boost_brand_configuration
**Users**: users (read for auth)
**Audit**: changelog, activity_logs

## Changelog Actions
- `creator_withdrawn` — Creator withdrew from campaign
- `creator_removed` — Brand removed creator
- `creator_interested` — Creator expressed interest
- `creator_joined` — Creator joined group

## MongoDB Collection (Boost)
**boost_ad_metrics** — Composed key: (campaign_id, ad_id, creator_id, moment_id, group_id). Stores platform metrics: views, likes, comments, shares, reach, saved, engagement, cpe, cpv, total_cost.
