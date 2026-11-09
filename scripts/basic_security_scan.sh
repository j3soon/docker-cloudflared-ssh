#!/bin/sh
set -eu
umask 077

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }

case "${1:-}" in
    local)
        [ "$#" -eq 1 ] || fail "usage: $0 local"
        need docker
        need jq
        cd "$(dirname "$0")/.."
        docker compose config --quiet || fail "invalid Compose configuration"
        container=$(docker compose ps -q cloudflared) || fail "cannot find container"
        [ -n "$container" ] || fail "cloudflared is not running"
        # Filter inspection in memory; never print command arguments or environment.
        docker inspect "$container" | jq -e '
            length == 1 and all(.[];
                .State.Running == true and
                (.Config.User | test("^[1-9][0-9]*(:[0-9]+)?$")) and
                .HostConfig.Privileged == false and
                (.HostConfig.CapAdd // [] | length == 0) and
                (.HostConfig.CapDrop | index("ALL") != null) and
                (.HostConfig.SecurityOpt | any(. == "no-new-privileges:true" or . == "no-new-privileges")) and
                (.HostConfig.PortBindings // {} | length == 0) and
                .HostConfig.NetworkMode != "host" and
                .HostConfig.PidMode != "host" and
                (.Mounts | length == 0) and
                (.HostConfig.ExtraHosts | any(. == "host.docker.internal:host-gateway" or . == "host.docker.internal=host-gateway")) and
                .HostConfig.RestartPolicy.Name == "unless-stopped")
        ' >/dev/null || fail "container hardening check failed"
        pass "running non-root connector, dropped capabilities, no new privileges"
        pass "no published ports, host namespaces, added capabilities, or mounts"
        pass "host gateway mapping and automatic restart configured"
        ;;
    remote)
        [ "$#" -eq 2 ] || fail "usage: $0 remote ssh.example.com"
        need curl
        hostname=$2
        case "$hostname" in
            ''|*[!a-zA-Z0-9.-]*|-*) fail "provide a hostname without a scheme, port, or path" ;;
        esac
        # No cookies, credentials, redirect following, or response bodies in output.
        # Probe the WebSocket upgrade used by client-side cloudflared SSH.
        result=$(curl -q -sS --noproxy '*' --connect-timeout 10 --max-time 20 \
            -o /dev/null -w '%{http_code} %{redirect_url}' \
            -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
            -H 'Sec-WebSocket-Version: 13' \
            -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
            "https://$hostname/") || fail "HTTPS probe failed"
        case "$result" in
            302\ https://*.cloudflareaccess.com/cdn-cgi/access/login/*|302\ https://"$hostname"/cdn-cgi/access/login/*)
                pass "trusted HTTPS endpoint redirects unauthenticated SSH upgrade to Access login" ;;
            *) fail "expected Access login redirect; check application hostname and policy" ;;
        esac
        printf '%s\n' 'Next: complete an SSH-key login from an external network before removing port forwarding.'
        ;;
    *) fail "usage: $0 local | remote ssh.example.com" ;;
esac
