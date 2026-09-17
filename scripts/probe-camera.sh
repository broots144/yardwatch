#!/usr/bin/env bash
# Probe the Amcrest main and sub RTSP streams directly and check them against
# what Frigate (H.264 for VAAPI) and BirdNET-Go (AAC, >= 16 kHz) need.
#
# Usage: scripts/probe-camera.sh        (reads CAM_IP CAM_USER CAM_PASS from .env)
# Needs: ffprobe, jq
# Exit:  0 all streams OK, 1 a stream needs a camera setting changed, 2 setup error.
#
# Run it from a host that can reach the camera VLAN, with Frigate stopped or not
# yet started if the firmware limits concurrent RTSP sessions.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${repo_root}/.env"

die() { echo "error: $*" >&2; exit 2; }

for bin in ffprobe jq; do
  command -v "$bin" >/dev/null || die "$bin not found in PATH"
done
[[ -f "$env_file" ]] || die "$env_file missing; copy .env.example to .env"

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

: "${CAM_IP:?CAM_IP not set in .env}"
: "${CAM_USER:?CAM_USER not set in .env}"
: "${CAM_PASS:?CAM_PASS not set in .env}"

urlencode() { jq -rn --arg s "$1" '$s|@uri'; }
user_enc="$(urlencode "$CAM_USER")"
pass_enc="$(urlencode "$CAM_PASS")"
base="rtsp://${user_enc}:${pass_enc}@${CAM_IP}:554/cam/realmonitor?channel=1"

failures=0

# probe <label> <UI label> <subtype>
probe() {
  local label="$1" Label="$2" subtype="$3" json err
  err="$(mktemp)"
  if ! json="$(ffprobe -v error -rtsp_transport tcp -timeout 10000000 \
      -print_format json -show_streams "${base}&subtype=${subtype}" 2>"$err")"; then
    echo "${label}: FAIL ffprobe could not open the stream: $(tr '\n' ' ' <"$err")"
    rm -f "$err"
    failures=$((failures + 1))
    return
  fi
  rm -f "$err"

  local vcodec width height fps acodec rate
  vcodec="$(jq -r '[.streams[]|select(.codec_type=="video")][0].codec_name // "none"' <<<"$json")"
  width="$(jq -r '[.streams[]|select(.codec_type=="video")][0].width // 0' <<<"$json")"
  height="$(jq -r '[.streams[]|select(.codec_type=="video")][0].height // 0' <<<"$json")"
  fps="$(jq -r '[.streams[]|select(.codec_type=="video")][0]
      | (if (.avg_frame_rate // "0/0") != "0/0" then .avg_frame_rate else (.r_frame_rate // "0/1") end)
      | split("/") | map(tonumber)
      | if .[1] == 0 then 0 else (.[0] / .[1] * 100 | round / 100) end' <<<"$json")"
  acodec="$(jq -r '[.streams[]|select(.codec_type=="audio")][0].codec_name // "none"' <<<"$json")"
  rate="$(jq -r '[.streams[]|select(.codec_type=="audio")][0].sample_rate // "0"' <<<"$json")"

  local verdict="OK" fixes=()
  if [[ "$vcodec" == "hevc" ]]; then
    fixes+=("Setting > Camera > Video > ${Label} Stream: set Encode Mode to H.264 (not H.265/H.265+); Frigate needs H.264 for VAAPI decode on Intel")
  elif [[ "$vcodec" == "none" ]]; then
    fixes+=("no video track; Setting > Camera > Video > ${Label} Stream: enable the stream, Encode Mode H.264")
  fi

  case "$acodec" in
    pcm_alaw|pcm_mulaw)
      fixes+=("Setting > Camera > Audio: set ${Label} Stream Encode Mode to AAC (it is G.711, ${acodec}) and Sampling Frequency to the highest offered (48k > 32k > 16k)")
      ;;
    none)
      if [[ "$label" == "main" ]]; then
        fixes+=("no audio track; Setting > Camera > Audio: enable Main Stream audio, Encode Mode AAC, Sampling Frequency the highest offered")
      fi
      ;;
  esac
  if [[ "$acodec" != "none" && "$acodec" != pcm_alaw && "$acodec" != pcm_mulaw && "$rate" -lt 16000 ]]; then
    fixes+=("Setting > Camera > Audio: raise ${Label} Stream Sampling Frequency from ${rate} Hz to the highest offered (48k > 32k > 16k); below 16 kHz bird song above 8 kHz is lost")
  fi
  ((${#fixes[@]})) && verdict="FAIL"

  printf '%s: %s video=%s %sx%s %sfps audio=%s %sHz\n' \
    "$label" "$verdict" "$vcodec" "$width" "$height" "$fps" "$acodec" "$rate"
  local f
  for f in ${fixes[@]+"${fixes[@]}"}; do
    echo "  change: $f"
  done
  [[ "$verdict" == "OK" ]] || failures=$((failures + 1))
}

probe main Main 0
probe sub Sub 1

if ((failures)); then
  echo "camera needs changes: ${failures} stream(s) failed" >&2
  exit 1
fi
