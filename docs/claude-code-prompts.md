# Claude Code work prompts

Run these in order from the repo root, one per session. Each prompt is self-contained; CLAUDE.md carries the shared context. Paste the block verbatim. Where a prompt says "verify against upstream", it means clone the named repo into `../` and read the source, not the README.

Gate between sessions: the camera is mounted and `ffprobe` shows an AAC audio track before session 2. Nothing after session 1 is worth doing on a camera that is still in the box.

---

## Session 1: repo hygiene and bring-up scripts

```
Read CLAUDE.md. This repo holds a docker compose stack for a backyard bird station. Do the following, committing each as its own conventional commit:

1. Add .gitignore (.env, artwork/custom/birds/*, frigate/media, __pycache__, .venv, *.pyc, .DS_Store) and a LICENSE (MIT, Workshop 144 LLC, 2026).
2. Add scripts/probe-camera.sh: takes CAM_IP CAM_USER CAM_PASS from .env, runs ffprobe (json output) on the main and sub RTSP URLs, and prints a one-line verdict per stream: video codec, resolution, fps, audio codec, sample rate. Exit non-zero and say exactly what to change in the Amcrest UI if audio is pcm_alaw/pcm_mulaw or the sample rate is under 16000, or video is hevc (Frigate wants H.264 for VAAPI on Intel).
3. Add scripts/smoke.sh: after `docker compose up -d`, wait for each service health (frigate :5000/api/version, birdnet-go :8090/api/v2/health or the nearest equivalent, fugleramme :8080/, yawamf :9852/, mosquitto via mosquitto_sub -C 1 -t '$SYS/#'). Then subscribe to topic `birdnet` for 120 s and print any detections. Fail loudly with which service is not answering.
4. Validate frigate/config.yml against Frigate 0.17's schema: clone https://github.com/blakeblackshear/frigate into ../frigate at the latest 0.17 tag and check every key we use exists with the type we gave it. Fix anything wrong and note what changed in the commit body. Pay attention to: preset names for input_args/output_args, the openvino model path and labelmap path in the 0.17 image, review.alerts.labels, snapshots.crop.
5. Validate birdnet-go/config.yaml the same way against https://github.com/tphakala/birdnet-go (internal/conf/config.go and defaults.go). Confirm realtime.rtsp.streams[].mediaMode and channelMode keys exist and the MQTT topic default. Fix and note.
Do not change the architecture. Do not add Kubernetes manifests.
```

## Session 2: Home Assistant package, tested

```
Read CLAUDE.md and homeassistant/yardwatch.yaml. The package listens to BirdNET-Go's MQTT topic `birdnet` and keeps a first-of-year species list in a trigger-based template sensor, then pushes only for new-for-year species at confidence >= 0.85.

1. Write tests/ha/ that spin up Home Assistant in docker (ghcr.io/home-assistant/home-assistant:stable) with this package loaded, a mosquitto broker, and a python publisher that replays fixture payloads in tests/ha/fixtures/*.json shaped exactly like BirdNET-Go's NoteWithBirdImage (keys per CLAUDE.md). Assert via the HA REST API:
   - first Cardinalis cardinalis at 0.91 -> sensor.yardwatch_year_list == 1, new_species == 'true'
   - second cardinal at 0.95 -> count stays 1, new_species == 'false'
   - a Poecile carolinensis at 0.70 -> count stays 1 (below gate)
   - the notify automation fires exactly once across those three (use notify.persistent_notification as the target in the test config and read persistent notifications back)
   - year rollover: set the sensor's stored year attribute to last year via a fixture restart and confirm the list resets on the next detection
2. Fix whatever the tests reveal in the package. Known weak spots: `this` is undefined on the very first evaluation; `attribute:` state triggers do not fire when the attribute value repeats; the rest_command response shape (`today.content`) needs checking against HA's rest_command response_variable docs.
3. Add a Lovelace card YAML (homeassistant/card.yaml) with: last detection with image, year-list count, and an iframe to the fugleramme kiosk.
Keep the push rule exactly as documented; do not loosen the gate to make a test pass.
```

## Session 3: plates pipeline (North American artwork for fugleramme)

```
Read CLAUDE.md and tools/plates/coverage.py. fugleramme has artwork for 14 of the 63 species in YARD. Build tools/plates/ as a uv project that fills the gap with public-domain North American plates and writes them into artwork/custom/ in fugleramme's custom-style format.

Constraints, all verified, do not re-derive:
- Wikimedia Commons API needs User-Agent "yardwatch-plates/<ver> (https://github.com/broots144/yardwatch; duobrien@gmail.com)" and returns 429 with Retry-After (30 to 40 s observed). Honor Retry-After exactly, single-threaded, cache every API response and every downloaded file under tools/plates/.cache/ keyed by URL so re-runs make zero network calls.
- Preferred sources, in order: Category:Birds of New York (Eaton) (Fuertes plates, birds on plain backgrounds, cut cleanly), Fuertes plates in Bird-Lore and National Geographic (1913 to 1920, PD-US), Category:The Birds of America (Audubon; busy backgrounds, cut worse, but iconic). Filter to LicenseShortName in {Public domain, CC0, CC BY-SA 4.0, CC BY 4.0} via imageinfo extmetadata; record the license per file.
- Output format is fugleramme's: artwork/custom/birds/<current-scientific-name-slug>.webp (transparent, longest side <= 1200, halo per fugleramme's add_bird.py), artwork/custom/manifest.json entries {"birds/<file>": {"source": "<key>", "url": "<commons file page>"}}, and artwork/custom/ATTRIBUTION.md with one section per source key. Use names.normalize from a fugleramme checkout at ../fugleramme so the filename is the current name, not BirdNET's label. Prefer importing fugleramme's tools/add_bird.py prepare/write_plate/record over reimplementing them.
- Background removal: rembg with the isnet-general-use model, then alpha-matte cleanup (erode 1 px, feather 2 px). Where the plate has several birds, keep the largest connected component only. Write a preview contact sheet (tools/plates/out/preview.png) of every cut on fugleramme's paper texture so a human can reject bad cuts before they ship.

Deliverables:
1. tools/plates/fetch.py: for each missing species (coverage.py --json), search Commons (srsearch = scientific name, then English name, each ANDed with "Fuertes" then "Audubon"), rank candidates (source preference, then image size), download the top 2, write tools/plates/candidates/<slug>/*.jpg plus a sidecar json with title, page url, license, artist.
2. tools/plates/cut.py: candidates -> cut-outs -> artwork/custom via the fugleramme helpers. Idempotent. `--only <slug>` and `--redo` flags.
3. tools/plates/README.md with the exact run order and the review step.
4. A pytest that runs cut.py on two committed fixture plates (small, PD) offline and checks the manifest and file naming, including one species whose BirdNET label differs from the current name (Accipiter cooperii -> astur-cooperii).
Run it for real only for these ten first, then stop and show the contact sheet: Carolina Chickadee, Tufted Titmouse, American Goldfinch, House Finch, Mourning Dove, Carolina Wren, Dark-eyed Junco, Eastern Bluebird, Baltimore Oriole, Ruby-throated Hummingbird.
```

## Session 4: yardlist service (the "full API")

```
Read CLAUDE.md. Build services/yardlist, a small Go or Python (FastAPI) service that is the single source of truth for "what has visited this yard", merging BirdNET-Go audio detections and YA-WAMF photo sightings. HA and future Workshop 144 apps talk to this, not to three upstreams.

Inputs:
- MQTT topic `birdnet` (BirdNET-Go NoteWithBirdImage JSON, keys per CLAUDE.md).
- MQTT topic `yawamf/#` for classified visual sightings (verify the actual topic and payload in https://github.com/Jellman86/YetAnother-WhosAtMyFeeder backend source; do not guess).
- Optional pull: BirdNET-Go /api/v2/analytics/species/summary for backfill on first start.

Model (SQLite, WAL, single file under /data):
- species(scientific PK, common, first_ever_at, first_this_year_at, year, art_available bool)
- events(id, at, scientific, kind audio|photo, confidence, source, clip_url, image_url, verified bool)  verified = a photo event with an audio match inside 5 min, or vice versa.
- daily(date, scientific, audio_count, photo_count)

REST (versioned /v1, JSON, no auth on the LAN network, bind 0.0.0.0:8700):
- GET /v1/lifelist  -> species with first_ever_at, sorted newest first
- GET /v1/yearlist?year=2026
- GET /v1/today  -> daily rows plus the best photo (highest classifier confidence) per species
- GET /v1/streaks -> per species, consecutive days present; and yard-level "days with >= 1 detection"
- GET /v1/firsts?since=  -> first-of-year and first-ever events, for the digest
- GET /v1/events?limit=&kind=&scientific=
- GET /v1/health
- SSE /v1/stream of new events (for a future app)

MQTT out (retained where noted):
- yardwatch/first_of_year  {scientific, common, at, kind, confidence, image_url}   not retained
- yardwatch/first_ever     same shape
- yardwatch/yearlist/count retained
- yardwatch/today/species  retained, JSON list
Publish Home Assistant MQTT discovery for a sensor per retained topic so HA needs zero YAML for the counts.

Rules:
- A species counts toward lists only at confidence >= 0.85 (config), or any confidence if a photo and audio agree inside 5 min.
- Year boundary in the configured TZ, not UTC.
- Idempotent on replay (dedupe on detectionId / YA-WAMF event id).
- Ship a Dockerfile, add the service to docker-compose.yml on the yardwatch network, and add a compose profile so it can be left out.
- Tests: unit tests for the counting rules and year rollover; an integration test that publishes fixture MQTT and asserts the REST responses.
- Then simplify homeassistant/yardwatch.yaml to consume yardwatch/* topics and drop the template-sensor year list, keeping the push rule identical.
```

## Session 5 (later): e-ink wall frame

```
Read CLAUDE.md. fugleramme already runs its Inky Impression driver on a Pi and reads a remote BirdNET-Go via FUGLERAMME_DETECTOR_URL, so the wall frame is a Pi Zero 2 W + Inky Impression 7.3" or 13.3" running upstream fugleramme unmodified, pointed at http://<homelab>:8090. Write docs/eink-frame.md: parts list with prices (label estimates), the install.sh flow from upstream docs/install.md, the env var to set, and how to mount our artwork/custom style on the Pi (rsync from the repo, or a read-only NFS export). Verify against https://github.com/arnegiacomo/fugleramme docs/install.md and docs/hardware.md; do not invent flags.
```

---

## Deferred, deliberately

- Dedicated outdoor microphone node. Decide after one week of camera-mic detections. If needed, it is a Pi 4 + PoE splitter + PUI AOM-5024L capsule + CM108 USB card in an IP66 box, streaming RTSP via mediamtx to BirdNET-Go as a second source named `mic`.
- eBird submission. Manual by design; BirdNET-Go's CSV export covers it.
- Anything that assumes a Merlin API. There is none.
