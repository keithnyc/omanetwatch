# OmaNetWatch

OmaNetWatch is a personal Omarchy shell plugin that monitors HTTP and TCP endpoints, shows their current state in a native bar popup, and sends outage and recovery notifications.

## Current features

- One background monitoring service, even with multiple monitors
- HTTP checks with an expected status code
- TCP host/port checks
- Independent interval, timeout, and failure threshold per endpoint
- Alert only on the transition to down; notify again on recovery
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
cp ~/.config/omarchy/plugins/keith.omanetwatch/config.example.json \
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
ln -s "$PWD" ~/.config/omarchy/plugins/keith.omanetwatch
omarchy-shell shell rescanPlugins
omarchy plugin enable keith.omanetwatch right
```

The plugin deliberately starts with two consecutive failures required before notification. This avoids alerting on a single transient timeout. The popup still shows every individual check result.

## Configuration

OmaNetWatch watches `~/.config/omanetwatch/targets.json` and reloads it automatically. The root is an array containing HTTP and/or TCP targets.

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

## Privacy

OmaNetWatch makes checks directly from your computer. Target configuration and
check history remain local in `~/.config/omanetwatch/targets.json` and
`~/.local/state/omanetwatch/history.json`; neither file belongs in this repository.

## License

MIT
