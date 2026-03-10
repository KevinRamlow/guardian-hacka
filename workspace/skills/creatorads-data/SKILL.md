---
name: creatorads-data
description: |
  Complete database knowledge for CreatorAds/Brandlovrs: Maestro (db-maestro-prod), Catalyst MySQL, BigQuery guardian dataset, MongoDB Atlas.
  Covers Guardian API, Guardian Agents API, Campaign Manager API, Creator API, SmartMatch RE, Guardian Ads Treatment.
  Use when writing SQL queries, understanding table relationships, investigating data flows
  (campaigns→moments→ads→actions→media_content→proofread_medias), debugging Guardian moderation,
  querying creator/campaign/brand data, understanding enums/status flows, or any database question.
  Triggers: "query", "database", "table", "schema", "SQL", "maestro", "catalyst", "BigQuery",
  "guardian data", "campaign data", "creator data", "media_content", "proofread", "creator_group_invites"
---

# CreatorAds Data Skill

## Platform Overview

The CreatorAds platform (Brandlovrs) is an influencer marketing platform connecting brands with creators.
Data lives across multiple databases and services:

| Database/Store | Service(s) | Purpose |
|---|---|---|
| **db-maestro-prod** (MySQL) | Guardian API, Campaign Manager API, Creator API, Guardian Ads Treatment | Core campaign, content, and moderation data |
| **db-catalyst** (MySQL) | Creator API, SmartMatch RE | Legacy creator profiles, brands, missions, wallets, ecommerce |
| **BigQuery guardian** dataset | Guardian Agents API | Semantic memory: tolerance patterns, error patterns, gold standards |
| **MongoDB Atlas** | SmartMatch RE | Creator embeddings, vector search, AI descriptions |

## Core Data Hierarchy

```
Brand → Campaign → Moment → Ad → Action → MediaContent → ProofreadMedia
                     ↑                                         ↓
              CreatorGroup ← CreatorGroupInvite           ProofreadGuideline
                                  ↑                            ↓
                              Creator                   GuardianEval (human feedback)
```

## Reference Files

Load the appropriate reference file based on the query domain:

### Database Schemas
- **[maestro-schema.md](references/maestro-schema.md)** — Complete Maestro DB schema (50+ tables). Load when writing queries against the main CreatorAds database or understanding table structures for campaigns, actions, media, guidelines, proofread results, boost, payments, users.
- **[catalyst-schema.md](references/catalyst-schema.md)** — Complete Catalyst DB schema (128 tables). Load when querying legacy creator profiles (colab_user), brand data (brand_dnb), missions, wallets, ecommerce orders, connectors, social credentials.

### Service-Specific References
- **[guardian-api.md](references/guardian-api.md)** — Guardian API tables, entities, and complex SQL queries. Load when working with content moderation, proofread_medias, guidelines evaluation, media approval/refusal flows, or the contest system.
- **[guardian-agents-api.md](references/guardian-agents-api.md)** — BigQuery semantic memory tables and MySQL pipeline queries. Load when working with tolerance_patterns, error_patterns, error_signals, guidelines_critiques_gold_standards, or understanding how Guardian learns from mistakes.
- **[campaign-manager-api.md](references/campaign-manager-api.md)** — Campaign Manager API tables and queries. Load when working with campaign CRUD, creator group management, invite workflows, boost ads, payment history, or content delivery tracking.
- **[creator-api.md](references/creator-api.md)** — Creator API tables and queries. Load when working with creator authentication, profiles, social credentials, devices, notifications, ratings, or the creator-facing campaign view.
- **[smartmatch.md](references/smartmatch.md)** — SmartMatch RE MongoDB collections and vector search. Load when working with creator search, semantic matching, embeddings, or the AI enrichment pipeline.

### Cross-Service References
- **[relationships.md](references/relationships.md)** — Cross-service entity relationships, shared tables, status enums, and data flow patterns. Load when investigating how data flows between services or when dealing with cross-service joins.
- **[common-queries.md](references/common-queries.md)** — Frequently used SQL queries for common investigations: campaign metrics, creator status, content approval rates, Guardian accuracy, payment reconciliation. Load when building analytical queries or debugging data.

## Quick Reference: Key Tables by Domain

**Campaigns**: campaigns, moments, ads, ads_attributes, formats, format_sources
**Creators**: colab_user (catalyst), creator_group_invites, creator_groups, creator_group_rewards
**Content**: actions, media_content, media_content_refused_guidelines, media_content_refused_reasons
**Moderation**: proofread_medias, proofread_guidelines, proofread_medias_audio_quality, proofread_medias_songs_audit, proofread_media_contest, proofread_pronunciation_results
**Guidelines**: guidelines, guidelines_critiques, improved_guidelines, guidelines_attachments
**Pronunciation**: pronunciation_targets, pronunciation_gold_standards, guideline_pronunciation_targets
**Evaluation**: guardian_evals, guardian_media_evals
**Payments**: creator_payment_history, creator_coupons, coupon_settings, brand_fee_settings
**Boost**: boost_ads, boost_facebook_business_oauth, boost_partnership_authorizations, boost_brand_configuration
**Users/Auth**: users, user_permissions, brand_users, brand_invites, organizations

## Quick Reference: Key Enums

**creator_group_invites.status**: refused, not_accepted, pending, participating, awaiting_approval, awaiting_response, paid, paid_partial, pending_payment
**guidelines.requirement**: MUST_DO, MUST_DO_NOT
**proofread_guidelines.classification**: CAPTIONS_GUIDELINE, PRONUNCIATION_GUIDELINE, BRAND_SAFETY, QUALITY, VIDEO_DURATION_GUIDELINE, GENERAL_GUIDELINE, CUSTOM_GUIDELINE
**campaign_states**: 1=draft, 2=active, 3=paused, 4=ended
**brand_users.role**: admin, editor, approver, viewer
**boost_ads.status**: pending, active, ended, awaiting_ended, failed
**boost_ads.channel**: instagram, tiktok, youtube
