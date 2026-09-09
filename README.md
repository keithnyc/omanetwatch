# OmaNetWatch

OmaNetWatch is an Omarchy shell plugin that monitors HTTP, TCP, and structured JSON status endpoints, shows their current state in a native bar popup, and sends state-change and recovery notifications.

![OmaNetWatch monitoring panel](preview.png)

## Current features

- One background monitoring service, even with multiple monitors
- HTTP checks with an expected status code
- TCP host/port checks
- JSON status checks with configurable field paths and health mappings
- Operational, degraded, outage, and unknown health states
- Independent interval, timeout, and failure threshold per endpoint
- Alert on non-operational state changes after the configured threshold; notify again on recovery
- Bar summary with a detailed, theme-aware popup
- Right-click the bar icon, or use the popup button, to check everything immediately
- Live reload when the targets file changes
- Rolling 30-check latency and availability history with a sparkline for each target
- History persisted across shell restarts in `~/.local/state/omanetwatch/history.json`

## Install

Install directly from GitHub and enable the bar widget:

```bash
omarchy plugin add https://github.com/keithnyc/omanetwatch.git --enable
```

Then create your configuration:

```bash
mkdir -p ~/.config/omanetwatch
cp ~/.config/omarchy/plugins/io.github.keithnyc.omanetwatch/config.example.json \
  ~/.config/omanetwatch/targets.json
```

Edit `~/.config/omanetwatch/targets.json` with the endpoints you want to monitor.

## Install for local development

Create the configuration file:

```bash
mkdir -p ~/.config/omanetwatch
cp config.example.json ~/.config/omanetwatch/targets.json
```

Install the plugin by linking this checkout into Omarchy's user plugin directory:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.keithnyc.omanetwatch
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.keithnyc.omanetwatch right
```

The plugin deliberately starts with two consecutive non-operational checks required before notification. This avoids alerting on a single transient timeout or malformed response. The popup still shows every individual check result and distinguishes degraded, outage, and unknown states.

## Configuration

OmaNetWatch watches `~/.config/omanetwatch/targets.json` and reloads it automatically. The root is an array containing HTTP, TCP, and/or JSON targets.

HTTP target fields:

- `name`: display name
- `type`: `http`
- `url`: complete `http://` or `https://` URL
- `expectedStatus`: expected HTTP response, default `200`

TCP target fields:

- `name`: display name
- `type`: `tcp`
- `host`: DNS name or IP address
- `port`: TCP port

JSON status target fields:

- `type`: `json`
- `url`: JSON endpoint URL
- `expectedStatus`: expected HTTP response, default `200`
- `statusPath`: field containing the provider status. Use a dot path such as `status.indicator` or a JSON Pointer such as `/status/indicator`.
- `statusMap`: maps exact, case-sensitive provider values to `operational`, `degraded`, `outage`, or `unknown`
- `reasonPath`: optional field containing a short human-readable description
- `sourceUrl`: optional status page shown in the popup; defaults to `url`

Missing fields, invalid JSON, oversized responses, and unmapped status values are reported as `unknown`; they are never treated as healthy. JSON responses are limited to 1 MiB. GitHub Status and Cloudflare Status examples are included in `config.example.json`, disabled by default.

Common optional fields:

- `id`: stable unique identifier; derived from `name` when omitted
- `enabled`: whether to schedule checks and alerts; default `true`. Disabled targets remain visible in the popup.
- `intervalSeconds`: seconds between checks, default `60`
- `timeoutSeconds`: per-check timeout, default `5`
- `failuresBeforeAlert`: consecutive failures before notifying, default `2`

## Dependencies

- Omarchy shell with third-party service and bar-widget support
- Python 3
- `omarchy-notification-send`

Plugins execute unsandboxed inside `omarchy-shell`. Review local and third-party plugin code before enabling it.

## Remove

Remove the plugin with Omarchy:

```bash
omarchy plugin remove io.github.keithnyc.omanetwatch
```

Removal leaves your target configuration and history intact. If you no longer
want that local data, you may separately delete
`~/.config/omanetwatch/targets.json` and
`~/.local/state/omanetwatch/history.json`.

## Privacy

OmaNetWatch makes checks directly from your computer. Target configuration and
check history remain local in `~/.config/omanetwatch/targets.json` and
`~/.local/state/omanetwatch/history.json`; neither file belongs in this repository.

## License

MIT
