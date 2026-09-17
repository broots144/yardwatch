# yardwatch

Backyard feeder station. One Amcrest PoE camera outside, everything else in containers.

```
Amcrest IP8M-T2599EW ─rtsp─▶ Frigate (go2rtc restream, bird detect, clips)
                                ├─▶ BirdNET-Go  (audio ID)  ─▶ fugleramme (wall frame, :8080)
                                └─▶ YA-WAMF     (photo ID, correlates with audio, :9852)
                    all ─mqtt─▶ Mosquitto ─▶ Home Assistant (first-of-year push, TTS, nightly digest)
```

## Bring-up

1. Camera (do this on the bench before it goes on the post):
   - static DHCP lease on the IoT VLAN, firewall rule: no WAN egress
   - Setting > Network > P2P off, cloud/"access platform" off
   - Setting > System > Account: user `frigate`, live + playback only
   - Setting > Camera > Video: main H.264 3840x2160 @ 15 fps, I-frame interval 15; sub H.264 at the largest size the firmware offers @ 10 fps
   - Setting > Camera > Audio: enable, AAC, highest sample rate offered, max bitrate, AGC and noise filter off
   - Setting > Camera > Conditions: day mode forced, IR off
   - verify from any box: `ffprobe rtsp://frigate:PASS@CAM_IP:554/cam/realmonitor?channel=1&subtype=0` and confirm an audio stream that is `aac` and its sample rate. If it says `pcm_alaw 8000 Hz` the audio setting did not take.
2. `cp .env.example .env`, fill it in.
3. `docker compose up -d mosquitto frigate`. Open http://host:5000, confirm the feeder camera is live and detect is running on the sub stream. Draw a motion mask over sky and swaying branches.
4. `docker compose up -d birdnet-go`. Open http://host:8090 > Settings > Audio, confirm the `feeder` RTSP source is receiving. Watch the live spectrogram for a few minutes.
5. `docker compose up -d fugleramme`. Open http://host:8080 and http://host:8080/admin. Set the lookback window (24 h is right for a frame; 4 h if you want it to feel live).
6. `docker compose up -d yawamf`. Open http://host:9852, run the setup wizard: Frigate URL `http://frigate:5000`, MQTT `mosquitto`, BirdNET-Go internal URL `http://birdnet-go:8080`, MQTT topic `birdnet`, source mapping `feeder` -> camera `feeder`.
7. Home Assistant: add `homeassistant/yardwatch.yaml` as a package, set the notify service and speaker, check the MQTT integration points at this broker.

## Mount geometry

- 2.8 mm lens, 105 deg. At 1 m the frame is ~2.6 m wide; a chickadee is ~180 px on the 4K stream and ~60 px on a 720p sub stream. Mount 0.8 to 1.5 m from the perch, looking slightly down, sun behind the camera.
- If sub-stream detections are flaky, move the detect role to the main stream in `frigate/config.yml` and set `detect: {width: 1920, height: 1080, fps: 5}`.

## Week-one falsification checklist

- BirdNET-Go: are confident detections (>= 0.8) arriving for birds you can see at the feeder? If the camera mic is too muffled you will see only the loud ones (cardinal, jay, wren). That is the signal to add a dedicated capsule mic as a second RTSP/USB source.
- Frigate: count bird events per day vs. what you see out the window. Below ~50% recall means the detect stream is too small or the camera is too far.
- HA: how many pushes did she get? More than 3 a day in September means the first-of-year gate is not doing its job (check `sensor.yardwatch_year_list` attributes).

## Artwork

fugleramme ships ~870 European plates. Of 63 common central Indiana yard species, 14 have art. `tools/plates/` fetches public-domain North American plates from Wikimedia Commons, cuts them, and writes them into `artwork/custom/` in fugleramme's format. See `tools/plates/README.md`.

## Not in scope yet

- The e-ink wall frame (needs a Pi Zero 2 W + Inky Impression; fugleramme supports it natively now that it reads the API remotely). Start with a tablet in kiosk mode on :8080.
- Dedicated outdoor microphone. Decide after week one.
