# SmartMatch RE — Database Usage

AI-native creator search and campaign matching platform using MongoDB Atlas Vector Search.

**Codebase**: `/Users/fonsecabc/brandlovrs/ai/agents/smartmatch-re` (Python, FastAPI)
**Databases**: MongoDB Atlas (primary), MySQL Catalyst + Maestro (secondary)

## MongoDB Collections

### social-aggregator-creator-ads (DB: social-analytics-hmlg)
Core creator profile data with embeddings for vector search.

| Field | Type | Notes |
|---|---|---|
| _id | ObjectId | |
| creator_id | Integer | Unique, maps to colab_user.id in Catalyst |
| name, username, bio, location | String | |
| city | Object | {id: int, name: string} |
| interests | Array[String] | |
| instagram.username | String | |
| instagram.followers | Integer | |
| instagram.following | Integer | |
| instagram.engagement_rate | Float | |
| instagram.is_hidden | Boolean | **INVIOLABLE: if True, creator is BLOCKED** |
| instagram.url | String | |
| embedding | Array[Float] | 384 dimensions, BAAI/bge-small-en-v1.5 |
| embedding_generated_at | DateTime | |
| audience_data | Object | Demographics |
| top_hashtags | Array[String] | |
| content_themes | Array[String] | |
| brand_collaborations | Array[String] | |
| brand_safety_score | Float | 0.0-1.0 |
| is_verified, is_active | Boolean | |

**Vector Search Index**: `creators_vector_search_v2` on `embedding` field (cosine similarity).

### creators-descriptions (DB: social-refined-hmlg)
AI-generated enriched creator descriptions.

| Field | Type | Notes |
|---|---|---|
| creator_id | Integer | |
| content_style | Array[String] | e.g. ["lifestyle", "fashion"] |
| creator_type | String | micro_influencer, mega_influencer, etc. |
| brands | Array[String] | Previously worked with |
| communication_style | Array[String] | |
| communication_language | Array[String] | |
| estimated_social_class | String | upper_middle, etc. |
| estimated_target_audience | Array[String] | |
| consumption_profile | String | |
| body_type | String | |
| environment, life_style, main_intention | Array[String] | |
| general_summary | String | AI-generated profile summary |

### instagram-business-discovery-users (DB: social-refined-hmlg)
Instagram business discovery insights and metadata.

## Key Queries

### Vector Search Pipeline
```javascript
db["social-aggregator-creator-ads"].aggregate([
  {
    "$vectorSearch": {
      "index": "creators_vector_search_v2",
      "path": "embedding",
      "queryVector": [/* 384-dim array */],
      "numCandidates": 200,
      "limit": 50,
      "filter": {
        "instagram.is_hidden": {"$ne": true},
        "instagram.followers": {"$gte": 3000, "$lte": 100000},
        "city.name": {"$in": ["São Paulo"]}
      }
    }
  },
  {
    "$project": {
      "creator_id": 1, "name": 1, "instagram": 1, "city": 1,
      "score": {"$meta": "vectorSearchScore"}
    }
  }
])
```

### Filter Search (Quick Search)
```javascript
db["social-aggregator-creator-ads"].find({
  "instagram.is_hidden": {"$ne": true},
  "instagram.followers": {"$gte": 3000, "$lte": 100000},
  "city.name": {"$in": ["São Paulo"]},
  "instagram.engagement_rate": {"$gte": 0.01}
}).limit(100)
```

### Get Blocked Creator IDs
```javascript
db["social-aggregator-creator-ads"].find(
  {"instagram.is_hidden": true},
  {"creator_id": 1}
).limit(100000)
```

### Store Embedding
```javascript
db["social-aggregator-creator-ads"].update_one(
  {"creator_id": id},
  {"$set": {"embedding": [/* 384-dim */], "embedding_generated_at": datetime}}
)
```

### City/Follower Distribution
```javascript
db["social-aggregator-creator-ads"].aggregate([
  {"$match": {"instagram.is_hidden": {"$ne": true}}},
  {"$bucket": {
    "groupBy": "$instagram.followers",
    "boundaries": [0, 1000, 5000, 10000, 50000, 100000, 500000, 1000000, 10000000],
    "output": {"count": {"$sum": 1}}
  }}
])
```

## API Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/v1/campaigns/search-creators` | Campaign-based semantic search |
| POST | `/api/v1/campaigns/quick-search` | Quick filter-based search |
| POST | `/api/v1/campaigns/semantic-search` | Text-based semantic search |
| POST | `/api/v1/campaigns/process-input` | Parse user input + search |
| GET | `/api/v1/campaigns/test-connection` | Connection test |
| GET | `/health` | Service health |

## Scoring System
- Semantic alignment: 35%
- Audience match: 30%
- Brand safety: 20%
- Engagement potential: 15%

## Embedding Model
**BAAI/bge-small-en-v1.5** via FastEmbed — 384 dimensions, cosine similarity, max 512 tokens.

## Config
```
MONGODB_URI, MONGODB_DATABASE=social-analytics-hmlg
MYSQL_HOST, MYSQL_PORT=3306, MYSQL_USER, MYSQL_PASSWORD
ACTIVE_CATALYST_DATABASE=db-catalyst-hmlg
ACTIVE_MAESTRO_DATABASE=db-maestro-hmlg
```
