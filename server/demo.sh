#!/usr/bin/env bash
# Make any family member do things from the terminal: for testing alone, and as
# the stage backup. Talks to http://localhost:3000 unless FAMILY_API is set:
#   FAMILY_API=https://<team-domain>.ngrok-free.app ./server/demo.sh family
set -euo pipefail

API="${FAMILY_API:-http://localhost:3000}"
API="${API%/}"

usage() {
  cat <<'EOF'
Usage: demo.sh <command> [args]

  family                    Everyone's vitals, distance inputs and status
  inbox   <member>          Unanswered events waiting for a member
  checkin <from> <to>       <from> asks <to> "Are you OK?"
  answer  <member> ok|help  <member> answers their newest check-in
  sos     <member>          <member> presses SOS
  fall    <member>          A fall is detected on <member>'s watch
  hr      <member> <bpm>    Set heart rate (above 150 or below 40 fires a health alert)
  spo2    <member> <pct>    Set SpO2 (below 90 fires a health alert)
  move    <member> <lat> <lon>  Set position
  reset                     Clear all events and statuses (run before each demo)

Members: dad, kid, mom, grandpa
Examples:
  demo.sh checkin kid dad   # Kid checks on Dad
  demo.sh sos grandpa       # Grandpa needs help; everyone else is alerted
EOF
}

# Pretty-print JSON from stdin (Node is already required for the server).
pretty() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.stringify(JSON.parse(s),null,2))}catch{console.log(s)}})'; }

req() { # req METHOD PATH [JSON]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" -H "Content-Type: application/json" -H "ngrok-skip-browser-warning: 1")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}" "$API$path"
}

need() { [[ $# -ge 1 && -n "$1" ]] || { usage; exit 1; }; }

cmd="${1:-}"; shift || true
case "$cmd" in
  family)  req GET /family | pretty ;;
  inbox)   need "${1:-}"; req GET "/members/$1/inbox" | pretty ;;
  checkin) need "${2:-}"; req POST "/members/$2/checkin" "{\"from\":\"$1\"}" | pretty ;;
  answer)
    need "${2:-}"
    id=$(req GET "/members/$1/inbox" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        const c=JSON.parse(s).filter(e=>e.type==="checkin").pop();
        if(!c){console.error("No unanswered check-in for that member.");process.exit(1)}
        console.log(c.eventId)})')
    req POST "/events/$id/ack" "{\"by\":\"$1\",\"response\":\"$2\"}" | pretty ;;
  sos)     need "${1:-}"; req POST "/members/$1/sos" '{"type":"manual"}' | pretty ;;
  fall)    need "${1:-}"; req POST "/members/$1/sos" '{"type":"fall"}' | pretty ;;
  hr)      need "${2:-}"; req POST "/members/$1/telemetry" "{\"hr\":$2}" | pretty ;;
  spo2)    need "${2:-}"; req POST "/members/$1/telemetry" "{\"spo2\":$2}" | pretty ;;
  move)    need "${3:-}"; req POST "/members/$1/telemetry" "{\"lat\":$2,\"lon\":$3}" | pretty ;;
  reset)   req POST /debug/reset | pretty ;;
  ""|-h|--help|help) usage ;;
  *) echo "Unknown command: $cmd"; usage; exit 1 ;;
esac
