# Docker Cloudflared SSH

Expose the host's existing OpenSSH server through Cloudflare Access using the official `cloudflare/cloudflared` image. The container runs unprivileged on a bridge network and publishes no ports. No Dockerfile is needed.

Requires Linux Docker Engine 20.10+, Docker Compose, host SSH listening on a Docker-reachable interface at TCP/22, and a domain managed on Cloudflare (DDNS alone is insufficient). Outbound-only tunneling works across public IP changes without DDNS.

## Cloudflare setup

Replace `ssh.example.com` below with your hostname.

1. [Create a remotely managed tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/) and copy its connector token privately.
2. [Create a self-hosted Access application](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/) for `ssh.example.com` before publishing the route. Add an [Allow policy](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/) with **Include (OR) → Emails → your exact email**. Avoid Everyone and Bypass policies.
3. In the tunnel's **Published application routes**, add `ssh.example.com` with service type **SSH** and URL **`host.docker.internal:22`** (`ssh://host.docker.internal:22`). Let Cloudflare create its DNS record. Do not use `localhost:22`, which refers to the container.

**Optional MFA:** first [configure MFA with a supported identity provider](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/mfa-requirements/), then add **Require (AND) → Authentication method → MFA** to the same Allow policy. The provider must report MFA to Cloudflare. Alternatively, follow the separate [Access independent MFA setup](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/independent-mfa/).

## Deploy

```sh
cp .env.example .env
chmod 600 .env
# Edit .env privately and replace REPLACE_ME with the tunnel token.
docker compose config --quiet
docker compose up -d
docker compose logs --tail=50
```

Confirm the tunnel is **Healthy** in the dashboard. Never commit or log the token. Full resolved Compose output and Docker command arguments expose it; restrict Docker administration access and redact logs before sharing.

## Connect

[Install cloudflared on the laptop](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/), then follow the [SSH client guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-cloudflared-authentication/). Add to `~/.ssh/config`, adjusting the username and executable path:

```sshconfig
Host my-server
    HostName ssh.example.com
    User your-user
    ProxyCommand cloudflared access ssh --hostname %h
```

```sh
ssh my-server
scp ./somefile my-server:~/
sftp my-server
```

Access opens a browser for authentication when needed, followed by normal SSH-key authentication. Verify the host-key fingerprint through a trusted connection.

## Safe cutover

Complete an SSH login from **another network** before removing the router's TCP/22 forward. Keep LAN or console recovery available. Then check public IPv6 ingress, UPnP, DMZ, and other forwarding rules; verify direct public-IP SSH is blocked while tunnel SSH still works. Keep host OpenSSH and LAN access running, and continue OS security updates: tunneling does not fix kernel CVEs.

## Troubleshooting and maintenance

- Origin failures: check host SSH, its listening interface, and host firewall access from Docker. Probe with `docker run --rm --add-host=host.docker.internal:host-gateway busybox nc -zvw3 host.docker.internal 22`.
- Tunnel failures: inspect `docker compose logs --tail=50`, the token, DNS, and outbound port 7844 (UDP or TCP).
- Access failures: check the hostname, identity policy, MFA, and laptop installation. SSH permission errors usually require checking the host username and authorized key.
- Update: run `docker compose pull && docker compose up -d`, then retest external SSH. Pin `image` to a known-good digest for reproducibility or rollback.
- Recovery: use LAN SSH or console. `docker compose down` stops this project without stopping host SSH. Rotate leaked tokens in Cloudflare, update `.env`, and run `docker compose up -d --force-recreate`.
