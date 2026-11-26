# Attaching a Domain & HTTPS/WSS to a Geo-Locked VPS

When a VPS is behind NAT port forwarding and regional geo-blocking, **Cloudflare Tunnel (`cloudflared`)** lets you attach a custom domain with automatic **HTTPS** and **WSS (`wss://`)** without changing firewall ports or exposing the raw IP.

## Why Cloudflare Tunnel Works Around Geo-Locks

- Instead of external players connecting directly to your VPS IP, the `cloudflared` container inside `server/` opens an **outbound** connection to Cloudflare's global edge (`443/7844`).
- Players connect to `wss://play.yourdomain.com/ws` and `https://play.yourdomain.com/api/...` via Cloudflare Anycast edge nodes worldwide (bypassing direct-IP geo-blocks while encrypting passwords & tokens over TLS).

## Setup Steps

1. **Create a Cloudflare Tunnel**
   - In the Cloudflare Zero Trust dashboard (**Networks -> Tunnels -> Create a tunnel -> Cloudflared**), copy your tunnel token.
   - Add a **Public Hostname** route:
     - Hostname: `play.yourdomain.com`
     - Service: `http://server:8080`
2. **Add Token to `/opt/worldwar-pixel/.env` on VPS**
   ```env
   CLOUDFLARE_TUNNEL_TOKEN=your_tunnel_token_here
   ```
3. **Start the Optional Tunnel Profile**
   ```bash
   cd /opt/worldwar-pixel
   docker compose --profile tunnel up -d
   ```
4. **Point Clients or Override for Testing**
   - Test with environment variable `WWP_SERVER_URL=wss://play.yourdomain.com/ws` in both `WorldWarPixel.exe` and `WorldWarPixel-Client.exe`, or update `defaultAccountAPIBase` (`launcher/account_api.go`) and `DEFAULT_SERVER_URL` (`scripts/network/mp_client.gd`) before building a release.
