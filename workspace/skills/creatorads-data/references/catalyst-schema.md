# Catalyst Database Schema (db-catalyst)

Legacy MySQL database for the Brandlovrs platform. Contains creator profiles, brand data, missions, wallets, ecommerce integrations, and social credentials. Used primarily by Creator API and SmartMatch RE.

## Table of Contents
- [Creator/Influencer Management](#creatorinfluencer-management)
- [Brand Management](#brand-management)
- [Missions & Campaigns](#missions--campaigns)
- [Wallet & Payments](#wallet--payments)
- [Ecommerce Integration](#ecommerce-integration)
- [Social Credentials](#social-credentials)
- [Notifications](#notifications)
- [Location & Demographics](#location--demographics)
- [Action Plans](#action-plans)
- [Internal Systems](#internal-systems)

---

## Creator/Influencer Management

### colab_user
Core creator/influencer table. Referenced as `creator_id` across Maestro tables.
| Column | Type | Notes |
|---|---|---|
| id | INT PK AUTO_INCREMENT | Referenced everywhere as creator_id |
| name | VARCHAR(255) | |
| email | VARCHAR(255) UNIQUE | |
| password | VARCHAR(255) | |
| termsUse | BOOLEAN | |
| first_access | BOOLEAN | |
| onboarding | BOOLEAN | |
| token | VARCHAR | |
| avatar | VARCHAR | |
| active | BOOLEAN | |
| created_at, deleted_at | TIMESTAMP | Soft delete |

### colab_user_data
Dynamic key-value profile attributes for creators.
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| fk_id_colab_user | INT FK → colab_user | |
| fk_id_colab_type_label | INT FK → colab_type_label | Type: City, State, Gender, etc. |
| value | VARCHAR | |

### colab_type_label
Labels for colab_user_data: City, State, Gender, Phone, CPF, BirthDate, etc.

### colab_type_data
Types of creator data: instagram, tiktok, youtube, etc.

### colab_user_x_interests
Junction: fk_id_colab_user → colab_user, fk_id_colab_interests → colab_interests.

### colab_interests
Interest categories for creators and brands.

### creator_ai_profiling
AI-generated creator profiles and classifications.

### creator_rating
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| fk_colab_user_id | INT FK → colab_user | |
| is_positive_rating | BOOLEAN | |
| rating_scope_id | INT FK → rating_scope | |
| comment | TEXT | |

### creator_size
Creator tier classifications (nano, micro, mid, macro, mega).

### creator_leads
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| tiktok_username, instagram_username | VARCHAR | |
| phone_number, city, email | VARCHAR | |
| campaign_id | INT | |
| accepted_terms, accepted_marketing | BOOLEAN | |

### creators_referrals / creators_referral_clicks
Referral tracking system for creator acquisition.

### colab_levels
Creator level classifications and progression.

### colab_levels_x_missions_x_reward
Level-specific mission rewards matrix.

---

## Brand Management

### brand_dnb
Core brand entity in Catalyst.
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| name | VARCHAR | |
| logo, brand_logo_url | VARCHAR | |
| isActive | BOOLEAN | |
| deleted_at | DATETIME | |

### brand_dnb_x_colab_user
Brand ↔ Creator assignments. Links brands to their creator network.

### brand_dnb_x_interests
Brand ↔ Interest categories.

### brand_dnb_x_influencer_invite
Brand invitations to specific influencers.

### brand_users
Brand team member accounts in Catalyst (separate from Maestro users).

### brand_status
Brand lifecycle status definitions.

### brand_goals
Available brand business goals.

### brand_accept_rule
Rules for accepting influencers: Automatic, Application, Invite.

### brand_gift / brand_gift_type / brand_gift_coupon / brand_gift_interest / brand_gift_x_targets
Gift/loyalty program system for brands.

### brand_ambassador_tags / brand_ambassador_form
Brand ambassador program management.

### challenges_x_brand_ambassador_tags
Links challenges to ambassador tags for targeting.

---

## Missions & Campaigns

### colab_missions
Legacy campaign/mission definitions.
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| brand_id | INT FK → brand_dnb | |
| name, description | VARCHAR/TEXT | |
| status | ENUM | |
| type | ENUM('LEGACY','LATEST') | |

### colab_missions_x_colab_user
Creator assignments to missions.

### mission_x_coupon_info
Coupon configuration per mission.

### colab_reward
Reward definitions for missions.

### coupon_type_discount
Discount types: percentual, fixed value, etc.

---

## Wallet & Payments

### colab_wallet
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| fk_id_colab_user | INT FK → colab_user | |
| value | DECIMAL | |
| status | ENUM('NOT_PAID','PROCESSING','PAID','ON_HOLD','REVERSED') | |
| fk_id_colab_type_operation | INT FK → colab_type_operation | |
| fk_id_colab_type_reward | INT FK → colab_type_reward | |

### colab_wallet_payment_type
Payment methods: PIX, Bank Transfer, etc.

### colab_wallet_payment_modality
Payment modalities.

### colab_coupon
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| fk_id_colab_user | INT FK → colab_user | |
| code | VARCHAR | Generated coupon code |
| fk_id_colab_missions | INT FK → colab_missions | |

### colab_coupon_history
Coupon usage tracking.

### direct_payment_history
Direct payment records.

---

## Ecommerce Integration

### orders
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| brand_id | INT FK → brand_dnb | |
| order_id | VARCHAR | External order ID |
| status | ENUM('PENDING','CONFIRMED','CANCELED') | |
| total_value | DECIMAL | |

### con_external / con_external_service
Connector definitions for external platforms (Shopify, WooCommerce, VTEX, etc.).

### con_setup_brand
Brand-specific connector configurations.

### con_config
Field-level connector configurations.

### con_history / con_execution / con_execution_history
Connector sync and execution tracking.

---

## Social Credentials

### instagram_credentials / instagram_business_credentials
| Column | Type | Notes |
|---|---|---|
| fk_id_colab_user | INT FK → colab_user | |
| instagram_business_username | VARCHAR | |
| instagram_business_id | VARCHAR | |
| long_term_access_token | VARCHAR | |
| is_connection_valid | BOOLEAN | |
| connection_type | VARCHAR | |

### tiktok_credentials
| Column | Type | Notes |
|---|---|---|
| fk_id_colab_user | INT FK → colab_user | |
| tiktok_username | VARCHAR | |

### youtube_credentials
| Column | Type | Notes |
|---|---|---|
| fk_id_colab_user | INT FK → colab_user | |
| youtube_channel | VARCHAR | |

### apple_credentials
| Column | Type | Notes |
|---|---|---|
| creator_id | BIGINT FK → colab_user | |
| apple_id | VARCHAR | |

---

## Notifications

### notification_center
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| title, description | VARCHAR/TEXT | |
| json_action | JSON | |
| logo | VARCHAR | |
| is_active | BOOLEAN | |
| fk_id_notification_type | INT FK | |
| fk_id_brand | INT FK → brand_dnb | |

### notification_center_x_creators
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| fk_id_notification_center | INT FK | |
| fk_colab_user_id | INT FK → colab_user | |
| was_viewed | BOOLEAN | |

---

## Location & Demographics

### state
Brazilian states (27 + Exterior). Columns: id, name, uf (2-char abbreviation).

### city
Brazilian cities. Columns: id, name, state_id FK → state.

### gender
Options: Homem, Mulher, Homem Trans, Mulher Trans, Não-binário, Prefiro não responder.

### address
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| postal_code | VARCHAR | |
| number, complement, street, neighborhood | VARCHAR | |
| user_id | INT FK → colab_user | |
| city_id | INT FK → city | |

### profile_user
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| is_phone_verified | BOOLEAN | |
| is_email_verified | BOOLEAN | |

---

## Action Plans

### actplan_plans / actplan_metrics / actplan_metrics_x_dnb
Action plan definitions and brand-specific metrics.

### actplan_status
Plan status: draft, active, completed, archived.

### actplan_tags / actplan_tags_x_plans / actplan_files
Organization and file management for action plans.

### actplan_todo_list / actplan_todo_status / actplan_todo_x_plan_x_status
TODO tracking within action plans.

---

## Internal Systems

### backoffice_users
Internal staff accounts.

### backoffice_events_log
Audit log for backoffice actions.

### catalyst_activity / catalyst_modules / catalyst_modules_access
User activity tracking and access control.

### devices
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| user_id | INT FK → colab_user | |
| app_version, model, platform, platform_version | VARCHAR | |
| push_token | VARCHAR | |
| UNIQUE | (user_id, model, platform) | |

### code_user
Verification codes for email/phone.
| Column | Type | Notes |
|---|---|---|
| id | INT PK | |
| user_id | INT FK → colab_user | |
| code | VARCHAR | |
| notification_type | VARCHAR | sms, email |
| expires_at | DATETIME | |
| used_at | DATETIME | |

### token_history
JWT token tracking: fk_id_colab_user, access_token, refresh_token.

### modash_report_sync
Modash analytics platform sync tracking.

### social_post_schedules / social_post_schedule_triggers / social_post_schedule_history
Social media post scheduling system.
