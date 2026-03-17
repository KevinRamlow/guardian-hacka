# Maestro Database Schema (db-maestro-prod)

The primary MySQL database for the CreatorAds platform. Used by Guardian API, Campaign Manager API, Creator API, and Guardian Ads Treatment.

## Table of Contents
- [Users & Auth](#users--auth)
- [Organizations & Brands](#organizations--brands)
- [Campaigns & Moments](#campaigns--moments)
- [Ads & Formats](#ads--formats)
- [Creator Groups & Invites](#creator-groups--invites)
- [Actions & Media](#actions--media)
- [Guidelines & Proofreading](#guidelines--proofreading)
- [Pronunciation](#pronunciation)
- [Guardian Evaluation](#guardian-evaluation)
- [Coupons & Payments](#coupons--payments)
- [Boost](#boost)
- [System & Config](#system--config)
- [Surveys](#surveys)
- [Changelog & Logging](#changelog--logging)

---

## Users & Auth

### users
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| name | VARCHAR(255) NOT NULL | |
| email | VARCHAR(255) NOT NULL UNIQUE | |
| password | VARCHAR(255) NOT NULL | |
| access_token | VARCHAR(800) | |
| user_type_id | INT FK → user_types | |
| last_login_at | TIMESTAMP | |
| last_brand_id | INT FK → brands | |
| phone | VARCHAR(20) | |
| two_factor_enabled | BOOLEAN DEFAULT FALSE | |
| two_factor_secret | VARCHAR(255) | |
| two_factor_backup_codes | VARCHAR(255) | |
| is_platform_admin | BOOLEAN DEFAULT FALSE | |
| photo_url | TEXT | |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### user_types
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| name | ENUM('creator','brand_user','organization_user','organization_owner') | |

### user_permissions
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| user_id | INT FK → users | |
| permission | ENUM('MANAGE_USERS','MANAGE_BRANDS','MANAGE_PERMISSIONS','MANAGE_LLM_PROMPTS','GUARDIAN_EVALS','BOOST_BRANDS','TAKE_RATE','CREATOR_MANAGEMENT','BOOST_MANAGE_LIMITS','GUARDIAN_OBJECTIONS','GUARDIAN_TEAM') | |
| UNIQUE | (user_id, permission) | |

### user_password_resets
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| user_id | INT FK → users | |
| token | VARCHAR(36) UNIQUE | |
| expires_at | TIMESTAMP NOT NULL | |
| used | BOOLEAN DEFAULT FALSE | |

---

## Organizations & Brands

### organizations
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| name | VARCHAR(100) NOT NULL | |
| owner_id | INT FK → users | |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### brands
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| name | VARCHAR(100) NOT NULL | |
| organization_id | INT FK → organizations | |
| brand_status_id | INT | |
| brand_slug | VARCHAR(150) | |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### brand_users
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| brand_id | INT FK → brands | |
| user_id | INT FK → users | |
| role | ENUM('admin','editor','approver','viewer') DEFAULT 'viewer' | |
| UNIQUE | (brand_id, user_id) | |

### brand_invites
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| brand_id | INT FK → brands | |
| invite_id | VARCHAR(36) | |
| role | ENUM('admin','editor','approver','viewer') | |
| name | VARCHAR(255) | |
| email | VARCHAR(255) | |
| expires_at | DATETIME | |

### brand_fee_settings
| Column | Type | Notes |
|---|---|---|
| brand_id | INT PK FK → brands | |
| default_take_rate | INTEGER DEFAULT 60 | Percentage |
| auto_approve_groups | BOOLEAN DEFAULT FALSE | |

### brand_x_social_media
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| brand_id | INT FK → brands | |
| instagram_username, tiktok_username, facebook_username, youtube_username, twitter_username | VARCHAR(255) | |

---

## Campaigns & Moments

### campaigns
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| campaign_state_id | INT FK → campaign_states | 1=draft, 2=active, 3=paused, 4=ended |
| brand_id | INT FK → brands | |
| title | VARCHAR(200) NOT NULL | |
| description | TEXT NOT NULL | |
| banner, thumbnail | VARCHAR(255) | |
| days_until_payment | SMALLINT NOT NULL | |
| main_objective | ENUM('brand_awareness','lead_generation','conversion') | |
| budget | DECIMAL(10,2) | |
| hashtag | VARCHAR(255) | |
| is_active | BOOLEAN DEFAULT FALSE | |
| published_at | DATETIME | |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### campaign_states
| id | name |
|---|---|
| 1 | draft |
| 2 | active |
| 3 | paused |
| 4 | ended |

### moments
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| campaign_id | INT FK → campaigns | |
| title | VARCHAR(200) NOT NULL | |
| description | TEXT NOT NULL | |
| budget | DECIMAL(10,2) | |
| status | ENUM | draft, published |
| starts_at, ends_at | DATETIME | |
| receive_content | DATETIME | Deadline for creator content submission |
| briefing_completion, matchmaking_submission, creators_approval, send_invitations | DATETIME | Workflow milestones |
| seed_product_name | VARCHAR(255) | |
| location, parameterized_link | VARCHAR(255) | |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### moments_custom_attributes
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| moment_id | INT FK → moments | |
| key | VARCHAR(255) | |
| value | TEXT | |
| UNIQUE | (moment_id, key) | |

### secondary_hashtags_moments
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| moment_id | INT FK → moments | |
| hashtag | VARCHAR(255) | |

---

## Ads & Formats

### ads
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| moment_id | INT FK → moments | |
| format_id | INT FK → formats | |
| title | VARCHAR(200) | |
| briefing | TEXT | |
| format_reference | VARCHAR(255) | |
| number_of_sequential_screens | INT | |
| published | BOOLEAN | |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### formats
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| format_source_id | INT FK → format_sources | Instagram, TikTok, YouTube |
| format_reference_type_id | INT FK → format_reference_types | |
| name | VARCHAR(100) | e.g. "Reels", "Story", "TikTok Video" |
| description | TEXT | |

### format_sources
Platform sources: Instagram, TikTok, YouTube, etc.

### format_reference_types
Reference types for ad formats.

### format_attributes
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| format_id | INT FK → formats | |
| name | VARCHAR(100) | e.g. "caption", "duration", "hashtag" |
| measurable | BOOLEAN | |

### ads_attributes
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| ad_id | INT FK → ads | |
| format_attribute_id | INT FK → format_attributes | |
| attribute_value | VARCHAR(255) | |
| assigned | BOOLEAN DEFAULT FALSE | |
| UNIQUE | (ad_id, format_attribute_id) | |

Caption requirement attribute IDs: 42 (Reels), 43 (Story), 48 (TikTok), 68 (YouTube Shorts).

---

## Creator Groups & Invites

### creator_groups
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| campaign_id | INT FK → campaigns | |
| title | VARCHAR(200) | |
| channel | ENUM | instagram, tiktok, youtube |
| status | ENUM | |
| creators_quantity_goal | INT | |
| is_creator_join_limited | BOOLEAN | |
| active_at, inactive_at, published_at | DATETIME | |
| meta_creators_positions | JSON | SmartMatch positions |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### creator_group_rewards
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| creator_group_id | INT FK → creator_groups (UNIQUE) | |
| reward_type_id | INT FK → reward_types | |
| reward_value | DECIMAL(10,2) | |

### reward_types
Cash, Discount, Product, etc.

### creator_group_moment
Junction: creator_group_id FK → creator_groups, moment_id FK → moments.

### creator_group_invites
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| creator_id | INT NOT NULL | FK to colab_user |
| creator_group_id | INT FK → creator_groups | |
| campaign_id | INT FK → campaigns | |
| reward_type_id | INT FK → reward_types | |
| reward_value | DECIMAL(10,2) | |
| fee_percentage | DECIMAL(5,2) | Take rate for this invite |
| status | ENUM | See status values below |
| accepted_at, refused_at, not_accepted_at | TIMESTAMP | |
| participating_at, interested_at, approved_at | TIMESTAMP | |
| paid_at | TIMESTAMP | |
| last_message_at | TIMESTAMP | |
| campaign_msgs | JSON | |
| ip_address | VARCHAR(45) | |
| performed_by | BIGINT | User who performed action |
| created_at, updated_at, deleted_at | TIMESTAMP | |
| INDEX | (creator_id) | |

**Status values**: refused, not_accepted, pending, participating, awaiting_approval, awaiting_response, paid, paid_partial, pending_payment

### creator_group_invites_additional_infos
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| creator_group_invite_id | INT FK → creator_group_invites | |
| observations | TEXT | |
| status_reason_type_id | INT FK → status_reason_types | |

### creator_group_invite_sm_positions
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| event | ENUM('ADD','DISCARD') | |
| user_id | INT FK → users | |
| creator_id | INT | |
| group_id | INT FK → creator_groups | |
| campaign_id | INT FK → campaigns | |
| origin | VARCHAR(255) | |
| index | INT | Position in SmartMatch results |
| hash_filter | VARCHAR(255) | |

### group_discarded_creators
Tracks creators discarded from groups: creator_id, group_id FK → creator_groups.

### status_reason_types
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| reason | VARCHAR(255) | |
| category | VARCHAR(100) | |
| description | TEXT | |

---

## Actions & Media

### actions
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| creator_id | INT NOT NULL | FK to colab_user |
| ad_id | INT FK → ads | |
| starts_at | DATETIME NOT NULL | |
| ends_at | DATETIME | |
| approved_at | TIMESTAMP | Brand approved content |
| approved_by | BIGINT | User who approved |
| refused_at | TIMESTAMP | Brand refused content |
| refused_by | BIGINT | User who refused |
| refusal_reason | VARCHAR(200) | |
| observation | TEXT | |
| received_product | BOOLEAN | |
| posted_at | TIMESTAMP | Creator posted content |
| created_at, updated_at, deleted_at | TIMESTAMP | |
| INDEX | (creator_id) | |

### media_content
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| action_id | INT FK → actions | |
| media_url | VARCHAR(255) | Original media URL |
| compressed_media_key | VARCHAR(255) | GCS path after compression |
| thumb_url | VARCHAR(255) | Thumbnail |
| mime_type | VARCHAR(100) | |
| filename | VARCHAR(500) | |
| approved_at | TIMESTAMP | |
| approved_by | BIGINT | |
| refused_at | TIMESTAMP | Brand refused this media |
| refused_by | BIGINT | |
| refusal_reason | TEXT | |
| is_refused_by_guardian | BOOLEAN DEFAULT FALSE | AI refused |
| storage_deleted_at | TIMESTAMP | When file removed from GCS |
| created_at, updated_at, deleted_at | TIMESTAMP | |

### media_content_refused_guidelines
Junction: media_content_id FK → media_content, guideline_id FK → guidelines. Tracks which guidelines caused brand refusal.

### media_content_refused_reasons
| Column | Type | Notes |
|---|---|---|
| media_content_id | INT FK → media_content | |
| refused_reason_type | ENUM('GUIDELINES_NOT_MET','GUIDELINE_NOT_LISTED','ANALYSIS_FAIL','CREATOR_DID_SOMETHING_NOT_SOLICITED','OTHER') | |

### media_content_x_ad_support_files
Junction: media_content_id FK → media_content, ad_id FK → ads.

---

## Guidelines & Proofreading

### guidelines
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| brand_id | INT FK → brands | |
| campaign_id | INT FK → campaigns | |
| moment_id | INT | Optional scope |
| ad_id | INT | Optional scope |
| guideline_critique_id | INT FK → guidelines_critiques | |
| guideline | TEXT NOT NULL | Full guideline text |
| requirement | ENUM('MUST_DO','MUST_DO_NOT') | |
| classification | ENUM('CAPTIONS','PRONUNCIATION','BRAND_SAFETY','QUALITY','DURATION','GENERAL') | |
| created_at, deleted_at | TIMESTAMP | |
| INDEX | (brand_id, campaign_id, moment_id, ad_id) | |

### guidelines_critiques
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| request_id | INT NOT NULL | Batch request ID |
| brand_id | INT FK → brands | |
| campaign_id | INT FK → campaigns | |
| moment_id, ad_id | INT | Optional scope |
| original_guideline | TEXT | |
| feedback_type | ENUM('NOT_APPLICABLE','ADJUST_CONTENT','MORE_INFORMATION','REMOVE_GUIDELINES','BREAK_IN_MANY','CHANGE_REQUIREMENT') | |
| requirement | ENUM('MUST_DO','MUST_DO_NOT') | |
| feedback | TEXT | AI-generated feedback |
| needs_review | BOOLEAN DEFAULT TRUE | |
| metadata | JSON | |

### improved_guidelines
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| guideline_critique_id | INT FK → guidelines_critiques | |
| improved_guideline | TEXT | Suggested improvement |

### guidelines_attachments
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| guideline_id | INT FK → guidelines | |
| path | VARCHAR(1024) | GCS path |
| mime_type | VARCHAR(255) | |

### proofread_medias
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| brand_id | INT FK | |
| campaign_id | INT FK | |
| moment_id, ad_id | INT | |
| action_id | INT FK → actions | |
| creator_id | INT | |
| media_id | INT FK → media_content | UNIQUE with deleted_at |
| uri | VARCHAR(1024) | GCS/S3 URI |
| adherence | FLOAT | Briefing adherence score 0-1 |
| is_safe | BOOLEAN | Brand safety verdict |
| is_copyrighted | BOOLEAN | Has copyrighted music |
| is_guidelines_approved | BOOLEAN | All guidelines passed |
| is_approved | BOOLEAN | Final AI verdict |
| correct_answers, incorrect_answers | INT | Guideline eval counts |
| metadata | JSON | Contains audio_output flag, etc. |
| created_at, deleted_at | TIMESTAMP | |
| INDEX | (brand_id, campaign_id, moment_id, ad_id) | |

### proofread_guidelines
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | |
| guideline_id | INT FK → guidelines | |
| proofread_media_id | INT FK → proofread_medias | |
| classification | ENUM | Same as guidelines.classification |
| guideline | TEXT | Guideline text snapshot |
| requirement | ENUM | MUST_DO, MUST_NOT_DO, SHOULD_DO, SHOULD_NOT_DO |
| answer | BOOLEAN | true=content satisfies guideline |
| justification | TEXT | AI reasoning |
| time | VARCHAR(50) | Video timestamp HH:MM |
| metadata | JSON | severity, reasoning, relevance_analysis, intent_consideration |
| created_at, deleted_at | TIMESTAMP | |
| INDEX | (guideline_id, proofread_media_id) | |

### proofread_medias_audio_quality
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| proofread_media_id | INT FK | |
| has_issues | BOOLEAN DEFAULT FALSE | |
| is_silent | BOOLEAN DEFAULT FALSE | |
| background_noise, background_music_too_loud, voice_volume_variations | TEXT | |

### proofread_medias_songs_audit
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| proofread_media_id | INT FK | |
| title | VARCHAR(255) | Song title |
| artists | VARCHAR(255) | Comma-separated |
| is_copyrighted | BOOLEAN | |

### proofread_media_contest
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| proofread_media_id | INT FK | |
| reason | TEXT | Creator's contest reason |
| status | VARCHAR(50) | PENDING, approved, rejected |
| analyst_id | INT FK → users | Human reviewer |
| decision_reason | TEXT | Analyst's reason |

---

## Pronunciation

### pronunciation_targets
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| brand_id | INT | |
| name | VARCHAR(255) | Brand/product name to pronounce |

### pronunciation_gold_standards
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| pronunciation_target_id | INT FK | |
| ipa | VARCHAR(500) | Correct IPA pronunciation |
| source | ENUM('MANUAL','LEARNED') | |

### guideline_pronunciation_targets
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| guideline_id | INT FK → guidelines | |
| pronunciation_target_id | INT FK | |
| threshold | DOUBLE DEFAULT 0.70 | Similarity threshold |

### proofread_pronunciation_results
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| proofread_guideline_id | INT FK → proofread_guidelines | |
| target_name | VARCHAR(255) | |
| timestamp_start, timestamp_end | DOUBLE | Video timestamps |
| extracted_ipa | VARCHAR(500) | What was pronounced |
| best_match_gold_ipa | VARCHAR(500) | Expected pronunciation |
| similarity_score | DOUBLE | 0-1 |
| approved | BOOLEAN | |

---

## Guardian Evaluation

### guardian_evals
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| user_id | INT FK → users | Human evaluator |
| proofread_guideline_id | INT FK → proofread_guidelines | |
| is_correct | BOOLEAN | Human agrees with AI |
| user_answer | BOOLEAN | Human's own decision |
| reason | VARCHAR(1024) | Explanation |
| media_evaluation_id | INT FK → guardian_media_evals | |

### guardian_media_evals
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| proofread_media_id | BIGINT FK | |
| user_id | BIGINT FK → users | |
| copyright_user_answer | BOOLEAN | |
| media_evaluation | BOOLEAN | |
| user_answer | BOOLEAN | |

---

## Coupons & Payments

### coupon_settings
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| moment_id | INT FK → moments | |
| discount_type | ENUM('NOMINAL','PERCENT') | |
| discount_value | DECIMAL(10,2) | |
| max_uses | INT | |
| prefix | VARCHAR(5) | |
| comission_value | DECIMAL(10,2) | |
| min_values | DECIMAL(10,2) | |

### creator_coupons
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| creator_id | INT | |
| brand_id | INT FK → brands | |
| coupon_settings_id | INT FK → coupon_settings | |
| code | VARCHAR(30) | UNIQUE with brand_id |
| external_id | VARCHAR(255) | |
| usage_count | INT | |
| last_use | DATETIME | |

### creator_payment_history
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| creator_id | INT | |
| campaign_id | INT FK → campaigns | |
| value | DECIMAL(10,2) | Net value |
| gross_value | DECIMAL(10,2) | Before fees |
| value_currency | ENUM('BRL','USD') DEFAULT 'BRL' | |
| status | VARCHAR(25) | |
| date_of_transaction | TIMESTAMP | |
| fund_transfer_orders_id | INT | |
| UNIQUE | (creator_id, campaign_id) | |

---

## Boost

### boost_ads
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| creator_id | BIGINT | |
| ad_id | BIGINT FK → ads | |
| campaign_id | BIGINT FK → campaigns | |
| moment_id | BIGINT | |
| group_id | BIGINT | |
| meta_ad_set_id | VARCHAR(255) | Meta/Facebook ad set ID |
| channel | VARCHAR(30) | instagram, tiktok, youtube |
| status | VARCHAR(20) | pending, active, ended, awaiting_ended, failed |
| budget | BIGINT | In cents |
| budget_spent | BIGINT DEFAULT 0 | In cents |
| start_date, end_date | DATETIME | |
| configuration | JSON | |

### boost_facebook_business_oauth
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| brand_id | INT FK → brands | |
| access_token | TEXT | |
| facebook_user_id, brand_business_id, brand_ad_account_id | VARCHAR(255) | |
| brand_page_id, brand_ig_user_id, brand_ig_username | VARCHAR(255) | |
| is_active | BOOLEAN DEFAULT TRUE | |

### boost_partnership_authorizations
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| brand_id | INT FK | |
| creator_id | INT | |
| creator_username | VARCHAR(100) | |
| channel | VARCHAR(100) | |
| status | VARCHAR(25) DEFAULT 'pending' | |

### boost_brand_configuration
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| brand_id | INT FK (UNIQUE) | |
| flag_authorization | BOOLEAN DEFAULT FALSE | |
| flag_boost | BOOLEAN DEFAULT FALSE | |

---

## System & Config

### llm_prompts
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| type | VARCHAR(200) | Prompt type identifier |
| version | VARCHAR(50) | |
| hash | VARCHAR(64) | |
| prompt | TEXT | |
| is_active | BOOLEAN DEFAULT FALSE | |
| published_at | TIMESTAMP | |
| published_by | VARCHAR(200) | |
| UNIQUE | (type, version) | |

### feature_flags
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| name | VARCHAR(255) UNIQUE | |
| enabled | BOOLEAN DEFAULT FALSE | |
| properties | TEXT | |

---

## Surveys

### surveys
id PK, name, question TEXT, created_at, deleted_at.

### survey_options
id PK, survey_id FK, content VARCHAR(255), has_justification BOOLEAN.

### survey_answers
id PK, survey_id FK, selected_options_ids JSON, justification TEXT, context JSON, user_id INT. UNIQUE(survey_id, user_id).

---

## Changelog & Logging

### changelog
| Column | Type | Notes |
|---|---|---|
| changelog_id | BIGINT PK | |
| brand_id, campaign_id, moment_id, group_id, creator_id, ad_id | BIGINT | Context fields |
| action | VARCHAR(100) | e.g. creator_withdrawn, creator_removed |
| origin | VARCHAR(100) | |
| old_values, new_values | JSON | |
| performed_by | BIGINT | |
| performed_at | TIMESTAMP | |

### activity_logs
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| request_id, correlation_id | VARCHAR(255) | |
| method | VARCHAR(16) | HTTP method |
| path | VARCHAR(1024) | |
| user | VARCHAR(255) | |
| payload, response | TEXT | |
| response_status | INT | |

### alerts
| Column | Type | Notes |
|---|---|---|
| id | BIGINT PK | |
| source | VARCHAR(100) | |
| event_type | VARCHAR(50) | |
| campaign_id, creator_id, ad_id, post_id | BIGINT | |
| channel | VARCHAR(50) | |
| metadata | JSON | |
| media_type | VARCHAR(50) | |
| posted_at | DATETIME | |
| post_duration, approved_post_duration | INT | |
| visual_similarity, audio_similarity | DECIMAL(5,4) | |
