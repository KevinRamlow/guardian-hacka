# Creator API — Database Usage

Creator-facing mobile API. Handles authentication, profiles, social credentials, campaign participation, content submission, notifications, and ratings.

**Codebase**: `/Users/fonsecabc/brandlovrs/app/creator-api` (Golang, GORM)
**Databases**: db-maestro-prod (MySQL) + db-catalyst (MySQL)

## Key Tables

### Authentication & User (Catalyst)
- **colab_user** — Core creator account (id, name, email, password, avatar, active, termsUse, first_access, onboarding)
- **token_history** — JWT tokens (fk_id_colab_user, access_token, refresh_token)
- **code_user** — Verification codes (user_id, code, notification_type, expires_at, used_at)
- **apple_credentials** — Apple sign-in (creator_id, apple_id)
- **profile_user** — Verification status (is_phone_verified, is_email_verified)

### Profile Data (Catalyst)
- **colab_user_data** — Dynamic key-value attributes (fk_id_colab_user, fk_id_colab_type_label, value). Types: City, State, Gender, Phone, CPF, BirthDate
- **user_utm_datas** — UTM tracking (user_id, utm_source, utm_medium, utm_campaign, utm_content, utm_term)
- **user_utm_interests** — Brand-specific UTM (user_id, brand_id, utm_source, etc.)

### Address (Catalyst)
- **address** — Creator address (postal_code, number, complement, street, neighborhood, user_id FK, city_id FK)
- **city** — (id, name, state_id FK)
- **state** — (id, name, uf)

### Social Credentials (Catalyst)
- **instagram_business_credentials** — (fk_id_colab_user, instagram_business_username, instagram_business_id, long_term_access_token, is_connection_valid, connection_type)
- **tiktok_credentials** — (fk_id_colab_user, tiktok_username)
- **youtube_credentials** — (fk_id_colab_user, youtube_channel)

### Campaign View (Maestro)
- **actions** — Creator's content submissions (ad_id, creator_id, approved_at, refused_at, posted_at)
- **media_content** — Submitted files (action_id, media_url, thumb_url, mime_type, filename)
- **ads_attributes** / **format_attributes** — Ad requirements
- **creator_group_invites** — Campaign participation status

### Notifications (Catalyst)
- **notification_center** — (title, description, json_action, logo, fk_id_notification_type, fk_id_brand)
- **notification_center_x_creators** — (fk_id_notification_center, fk_colab_user_id, was_viewed)

### Devices (Catalyst)
- **devices** — (user_id, app_version, model, platform, platform_version, push_token). UNIQUE(user_id, model, platform). Uses UPSERT.

### Ratings (Catalyst)
- **creator_rating** — (fk_colab_user_id, is_positive_rating, rating_scope_id FK, comment)
- **rating_scope** — (id, name)

### Leads (Catalyst)
- **creator_leads** — (tiktok_username, instagram_username, phone_number, city, campaign_id, email, accepted_terms, accepted_marketing)

### Ad Publications (Maestro)
- **ad_publications** — (ad_id, creator_id, caption, platform, post_type, status, sent_at, published_at)

## Key Queries

### Get Address with Location
```sql
SELECT a.*, c.name as city_name, c.id as city_id, s.name as state_name, s.uf
FROM address a
LEFT JOIN city c ON c.id = a.city_id
LEFT JOIN state s ON s.id = c.state_id
WHERE a.user_id = ? AND a.deleted_at IS NULL
```

### Get Verification Code with Email
```sql
SELECT cu.*, u.email
FROM code_user cu
JOIN colab_user u ON u.id = cu.user_id
WHERE cu.code = ? AND cu.used_at IS NULL AND cu.expires_at > NOW()
```

### Get Notifications (Paginated)
```sql
SELECT ncxc.*, nc.title, nc.description, nc.json_action, nc.logo,
       nc.created_at, bnb.name as brand_name, bnb.brand_logo_url
FROM notification_center_x_creators ncxc
INNER JOIN notification_center nc ON ncxc.fk_id_notification_center = nc.id
LEFT JOIN brand_dnb bnb ON bnb.id = nc.fk_id_brand
WHERE ncxc.fk_colab_user_id = ?
  AND EXISTS (SELECT 1 FROM colab_user cu WHERE cu.id = ncxc.fk_colab_user_id AND cu.deleted_at IS NULL)
ORDER BY nc.created_at DESC
LIMIT ? OFFSET ?
```

### Get Media Filename by Ad and Creator
```sql
SELECT media_content.filename
FROM media_content
JOIN actions ON actions.id = media_content.action_id
WHERE actions.ad_id = ? AND actions.creator_id = ?
  AND media_content.deleted_at IS NULL AND actions.deleted_at IS NULL
```

### Daily Tasks for Creator
Complex query joining campaigns → moments → ads → actions → creator_group_invites to build the creator's daily task list with status calculations.

### Count Coupons, Gifts, Contents
Three separate aggregation queries (TotCoupons, TotGifts, TotContents) that count available rewards for a creator across missions, levels, and ambassador tags.
