# Cross-Service Relationships & Data Flow

## Shared Tables Across Services

| Table | Guardian API | Campaign Manager | Creator API | Guardian Agents | Ads Treatment |
|---|---|---|---|---|---|
| campaigns | R | RW | R | - | - |
| moments | R | RW | R | - | - |
| ads | R | RW | R | - | - |
| actions | R | RW | RW | R | - |
| media_content | RW | RW | R | R | W |
| proofread_medias | RW | R | - | R | - |
| proofread_guidelines | RW | R | - | R | - |
| guidelines | R (catalyst) | R | - | R | - |
| creator_group_invites | R | RW | R | - | - |
| creator_groups | R | RW | - | - | - |
| brands | R | R | - | - | - |
| colab_user | R | - | RW (catalyst) | - | - |
| guardian_evals | RW | - | - | - | - |

R = Read, W = Write, RW = Read/Write

## Creator Identity Across Databases

The `creator_id` field used across Maestro tables (actions, creator_group_invites, proofread_medias, etc.) maps to `colab_user.id` in the **Catalyst** database. There is no `creators` table in Maestro — creator profile data lives in Catalyst's `colab_user` + `colab_user_data`.

In MongoDB (SmartMatch), `creator_id` in the `social-aggregator-creator-ads` collection also maps to `colab_user.id`.

## Brand Identity Across Databases

- **Maestro**: `brands` table (id, name, organization_id)
- **Catalyst**: `brand_dnb` table (id, name, logo, isActive)
- These are **separate tables** with **separate IDs** — the `brand_id` in Maestro tables refers to `brands.id`, while `brand_id` in Catalyst tables refers to `brand_dnb.id`. They share the same IDs by convention but are not FK-linked.

## Complete Data Flow: Campaign Lifecycle

```
1. BRAND SETUP
   brands (maestro) ← brand_users ← users
   brand_dnb (catalyst) ← brand settings

2. CAMPAIGN CREATION (Campaign Manager API)
   campaigns → moments → ads → ads_attributes
                           ↓
                        formats ← format_sources

3. CREATOR RECRUITMENT (Campaign Manager + SmartMatch)
   creator_groups → creator_group_rewards
   creator_groups → creator_group_moment → moments
   SmartMatch (MongoDB vector search) → creator_group_invite_sm_positions
   creator_group_invites (status: pending → participating)

4. GUIDELINE SETUP (Campaign Manager + Guardian API)
   guidelines (campaign/moment/ad level)
   guidelines_critiques → improved_guidelines (AI feedback)
   pronunciation_targets → pronunciation_gold_standards

5. CONTENT SUBMISSION (Creator API)
   actions (creator submits for ad)
   media_content (files uploaded)

6. VIDEO COMPRESSION (Guardian Ads Treatment)
   media_content.compressed_media_key ← GCS compressed video

7. AI MODERATION (Guardian API)
   proofread_medias ← AI verdict (is_approved, is_safe, adherence)
   proofread_guidelines ← per-guideline evaluation (answer, justification)
   proofread_medias_audio_quality ← audio analysis
   proofread_medias_songs_audit ← copyright check
   proofread_pronunciation_results ← pronunciation validation
   If auto-refusal: media_content.is_refused_by_guardian = true

8. HUMAN REVIEW (Guardian API)
   guardian_evals ← human feedback on guideline decisions
   guardian_media_evals ← human feedback on overall media
   proofread_media_contest ← creator disputes AI decision

9. BRAND APPROVAL (Campaign Manager API)
   media_content.approved_at / refused_at ← brand decision
   media_content_refused_guidelines ← which guidelines failed
   actions.approved_at / refused_at ← final action status
   actions.posted_at ← creator posts content

10. PAYMENT (Campaign Manager API)
    creator_payment_history ← payment records
    creator_coupons ← coupon generation

11. BOOST (Campaign Manager API)
    boost_ads ← promoted content
    boost_ad_metrics (MongoDB) ← performance data

12. LEARNING (Guardian Agents API → BigQuery)
    error_signals ← from contests + brand refusals
    error_patterns ← clustered error types
    tolerance_patterns ← brand tolerance analysis
    rejected_guidelines_with_disagreement ← disagreement tracking
```

## Status Flow: Creator Group Invite

```
                    ┌─→ refused
                    │
pending ─→ awaiting_approval ─→ awaiting_response ─→ participating ─→ paid
                    │                                      │           paid_partial
                    └─→ not_accepted                       └─→ pending_payment
```

## Status Flow: Media Content

```
Submitted (media_content created)
    ↓
Compressed (compressed_media_key set by guardian-ads-treatment)
    ↓
AI Moderated (proofread_medias created)
    ├─→ AI Approved (is_approved=true) → Awaiting Brand Review
    │       ├─→ Brand Approved (approved_at set)
    │       └─→ Brand Refused (refused_at set, media_content_refused_guidelines)
    └─→ AI Refused (is_approved=false, media_content.is_refused_by_guardian=true)
            └─→ Creator Contest (proofread_media_contest)
                    ├─→ Contest Approved → Awaiting Brand Review
                    └─→ Contest Rejected
```

## Key Join Patterns

### Campaign → Creator Content Chain (6-table join)
```sql
media_content mc
→ actions a ON a.id = mc.action_id
→ ads ad ON ad.id = a.ad_id
→ moments m ON m.id = ad.moment_id
→ campaigns c ON c.id = m.campaign_id
→ brands b ON b.id = c.brand_id
```

### Proofread → Guideline Source
```sql
proofread_guidelines pg
→ proofread_medias pm ON pm.id = pg.proofread_media_id
→ guidelines g ON g.id = pg.guideline_id  -- Catalyst DB
```

### Creator Group → Content Delivery
```sql
creator_group_invites cgi
→ creator_groups cg ON cg.id = cgi.creator_group_id
→ creator_group_moment cgm ON cgm.creator_group_id = cg.id
→ moments m ON m.id = cgm.moment_id
→ ads a ON a.moment_id = m.id
→ actions act ON act.ad_id = a.id AND act.creator_id = cgi.creator_id
```

## GCP Projects
- Homolog: `brandlovrs-homolog` (note: missing 'e')
- Production: `brandlovers-prod`
- BigQuery dataset: `guardian` in both projects
