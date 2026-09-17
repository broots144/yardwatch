# yardwatch

Backyard feeder station for Dustin (Workshop 144). One Amcrest IP8M-T2599EW PoE camera outdoors; all compute in containers on the homelab. The audience is Dustin's wife, who uses the Merlin app; the goal is a wall frame and phone pushes that feel like a naturalist's plate, not a dashboard.

## Architecture (settled, do not relitigate)

- Zero outdoor compute. No Raspberry Pi outside. Camera only.
- Frigate owns the camera. Its go2rtc restream (`rtsp://frigate:8554/feeder`) is the only RTSP client on the camera; BirdNET-Go and anything else read from go2rtc.
- BirdNET-Go does audio ID. It publishes one JSON per detection on MQTT topic `birdnet` and exposes `/api/v2`.
- fugleramme (upstream `ghcr.io/arnegiacomo/fugleramme`) renders BirdNET-Go detections as 1800s plates. It reads BirdNET-Go over the network via `FUGLERAMME_DETECTOR_URL`. No fork is needed for that; we only add a `custom` artwork style.
- YA-WAMF does photo species ID on Frigate `bird` events and correlates with BirdNET-Go audio.
- Home Assistant does notifications. Rule: a push only for first-of-year species at confidence >= 0.85 inside waking hours; everything else goes to the frame and the nightly digest.

## Verified facts (checked against upstream source, Sept 2026)

- BirdNET-Go MQTT payload keys: `CommonName`, `ScientificName`, `Confidence` (0..1), `ClipName`, `BeginTime`, `Date`, `Time`, `detectionId`, `sourceId`, `sourceName`, `BirdImage.url`. Go field names, PascalCase, except the lowercase ones listed. Audio for a detection: `GET /api/v2/audio/{detectionId}` (waits for encoding).
- BirdNET-Go analytics: `GET /api/v2/analytics/species/summary?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD` returns rows with `common_name`, `scientific_name`, `count`.
- BirdNET-Go RTSP stream config lives under `realtime.rtsp.streams[]` with `name,url,enabled,type,transport,channelMode,mediaMode,gain`. `mediaMode: audio-only` requests only the audio track.
- fugleramme custom style: `assets/artwork/custom/birds/<genus>-<species>.webp` (or `.png`), variants `-2`, `-3`. Filenames use the CURRENT scientific name after `assets/birdnet_aliases.json` (e.g. Cooper's Hawk is `astur-cooperii`, not `accipiter-cooperii`). `manifest.json` maps `birds/<file>` to `{"source": <key>, "url": <plate url>}`; `ATTRIBUTION.md` describes each source key. `tools/add_bird.py` in the fugleramme repo does naming, halo, WebP, manifest. Select the style at `:8080/admin`.
- fugleramme coverage: 14 of 63 common central-Indiana yard species have plates in the shipped `classic` style (list in `tools/plates/coverage.py`).
- Amcrest IP8M-T2599EW: 8MP, 2.8 mm / 105 deg fixed lens, built-in mic, IP67, PoE, 4K@15 fps, RTSP `rtsp://user:pass@ip:554/cam/realmonitor?channel=1&subtype=0` (sub: `subtype=1`). Dahua OEM. Audio defaults to G.711 8 kHz; set AAC at the highest sample rate offered in the camera UI or bird song above 4 kHz is gone.
- YA-WAMF: monolith image `ghcr.io/jellman86/yawamf-monalithic` (tags `latest`, `latest-cpu`, `latest-intel`, `latest-cuda`), needs Frigate 0.17+, config via `FRIGATE__*` env, BirdNET topic set in its UI to `birdnet`, source mapping camera `feeder` -> BirdNET source name `feeder`.
- Wikimedia Commons API: requires a descriptive `User-Agent` with contact info, returns 429 with `Retry-After` (30 to 40 s observed) from shared egress IPs. Any fetch tool must honor `Retry-After`, cache responses on disk, and cap concurrency at 1.
- Merlin has no API or export. Do not design integrations that depend on one.

## Conventions

- Compose is the deployment unit. No Helm until it has run for a month.
- Secrets only in `.env` (gitignored). Configs may reference `${VARS}`.
  - Exception, Frigate: `frigate/config.yml` must use `{FRIGATE_NAME}` (single braces, no `$`), and only env vars whose names start with `FRIGATE_` are substituted. Frigate runs Python `str.format` over go2rtc streams and camera input paths, so `${VAR}` or a non-`FRIGATE_` name raises KeyError and go2rtc does not start. Pass values from `.env` to the container as `FRIGATE_*` in `docker-compose.yml`. Literal `{` or `}` in a substituted value (e.g. the camera password) also breaks it. Verified against v0.17.2 `docker/main/rootfs/usr/local/go2rtc/create_config.py` and `frigate/config/env.py`.
- Python tools: `uv`, `pyproject.toml` per tool dir, ruff, type hints, no notebooks.
- Every claim in docs is labeled fact / estimate / guess when it is not verifiable from this repo.
- No em dashes or en dashes anywhere, including generated docs and commit messages.
- Commit messages: conventional commits, imperative, one logical change each.

## Layout

```
docker-compose.yml        the stack
.env.example              host-specific values
birdnet-go/config.yaml    BirdNET-Go overrides (Lebanon IN, RTSP from go2rtc, MQTT)
frigate/config.yml        Frigate 0.17 + go2rtc for the Amcrest
mosquitto/mosquitto.conf
homeassistant/yardwatch.yaml   HA package: sensors, first-of-year push, nightly digest
artwork/custom/           fugleramme custom style (bind-mounted read-only)
tools/plates/             plate fetch/cut pipeline (to be built; see docs/claude-code-prompts.md)
docs/claude-code-prompts.md    ordered work prompts for Claude Code sessions
```
