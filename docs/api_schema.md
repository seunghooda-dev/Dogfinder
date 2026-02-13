# DogFinder API Schema v0 (Draft)

## Goals
- Support multi-device sync for lost/sighting/tip data.
- Make matching and activity state consistent across users.
- Enable push notifications for nearby incidents and match updates.

## Auth
- `POST /v1/auth/email/signup`
- `POST /v1/auth/email/login`
- `POST /v1/auth/social/kakao`
- `POST /v1/auth/social/naver`

Response:
- `accessToken`
- `refreshToken`
- `user { id, email, displayName }`

## Core Models
- `DogProfile`
  - `id`, `ownerUserId`, `name`, `size`, `colors[]`, `breed`, `collarState`, `collarDesc`, `memo`
- `Post`
  - `id`, `type(lost|sighting)`, `status(active|resolved)`, `createdAt`, `eventTime`
  - `areaText`, `latitude`, `longitude`, `distanceKm`
  - `size`, `colors[]`, `breedGuess`, `collarState`
  - `title`, `body`, `ownerUserId`, `linkedDogId`, `photoUrl`, `contactPhone`, `openChatUrl`
- `TipReport`
  - `id`, `postId`, `createdAt`, `seenTime`, `seenAreaText`
  - `situation`, `memo`, `canCall`, `canChat`, `reporterUserId`

## Post APIs
- `GET /v1/posts?type=&status=&lat=&lng=&radiusKm=&cursor=`
- `GET /v1/posts/{postId}`
- `POST /v1/posts`
- `PATCH /v1/posts/{postId}` (resolve/update)
- `DELETE /v1/posts/{postId}`

## Tip APIs
- `GET /v1/posts/{postId}/tips`
- `POST /v1/posts/{postId}/tips`

## Dog APIs
- `GET /v1/dogs/me`
- `POST /v1/dogs`
- `PATCH /v1/dogs/{dogId}`
- `DELETE /v1/dogs/{dogId}`

## Media
- `POST /v1/media/upload-url` -> presigned URL
- Client uploads image to storage
- `photoUrl` saved in `Post`

## Matching
- `GET /v1/posts/{postId}/matches?limit=20`
- Server scoring inputs:
  - distance, time overlap, size, color overlap, collar state, breed similarity

## Notifications
- Device token register:
  - `POST /v1/push/tokens`
- Notification types:
  - `nearby_new_lost`
  - `nearby_new_sighting`
  - `match_candidate_found`
  - `tip_added_to_my_post`
  - `post_resolved`

## Suggested DB (initial)
- `users`
- `dogs`
- `posts`
- `tips`
- `push_tokens`
- indexes:
  - `posts(type, status, createdAt desc)`
  - geo index on `posts(latitude, longitude)`
  - `tips(postId, createdAt desc)`

## Rollout Plan
1. Add backend repo with these endpoints and JWT auth.
2. Add Flutter repository layer and switch local store to remote sync.
3. Add push token registration and notification handling.
