# Dashboard for KUAL

A landscape dashboard for a jailbroken Kindle Paperwhite 3 / 7th
generation (1448 x 1072). It fetches current conditions, daily values, and a 12-hour forecast from Open-Meteo,
renders directly to the framebuffer with FBInk, and keeps the last successful
response for offline use.

## What this first version includes

- Current temperature, conditions, apparent temperature, wind, and rain chance
- A 12-hour forecast grouped into similar periods, with prominent rain/snow/storm changes
- Today high/low, rain chance, apparent temperature, and wind
- Daily quotes fetched from GitHub, with cached and bundled offline fallbacks
- Five-minute request throttling and offline cache fallback
- A large-type editorial layout with a bitmap-font fallback
- KUAL actions for normal display and forced refresh
- Deep-sleep refresh loop that leaves the dashboard visible
- RTC wakeups for unattended weather refreshes

Persistent boot-time installation is intentionally not included.

## Sleep and automatic refresh behavior

Choose **Start Dashboard (Sleep + Auto Refresh)** to launch the low-power mode.
It pauses the native Kindle interface, records its original framebuffer
rotation, and turns it one raw rotation step into landscape so Amazon's screensaver cannot overwrite
the dashboard, fetches and renders the latest data, arms an RTC alarm, and
suspends directly to memory. The e-ink panel keeps the last frame visible while
the CPU sleeps. On an RTC or power-button wake, it waits for the device to
settle, refreshes the data, redraws, and suspends again. Stopping Dashboard
restores the saved rotation before returning to the native interface.

To leave Dashboard, briefly press the power button while it is sleeping. An
early wake is treated as an exit request: Dashboard restores portrait mode and
starts the normal Kindle interface. A long forced-restart press is unnecessary.

The default interval is one hour. Change `REFRESH_INTERVAL_SECONDS` in
`config.sh`, but keep it at 300 seconds or longer. Wi-Fi is enabled only for the
bounded fetch and disabled before each suspend.

Before starting the hourly mode, use **Run 10-Minute Sleep Test**. The display
should retain the dashboard, flash with refreshed Ithaca data after roughly ten
minutes, and then suspend again.

Dashboard mode is deliberately not installed at boot. During the initial
device test, restart the Kindle to exit and recover the normal UI. The KUAL
**Stop Dashboard / Return Home** action is also provided for cases where KUAL
remains reachable or the daemon is stopped through USBNetwork.

This mode writes only to runtime controls under `/sys` and does not modify the
read-only root filesystem. RTC and suspend interfaces vary across Kindle
firmware, so first test with the Kindle charged and an interval of at least ten
minutes before relying on unattended operation.

## Install

1. Install FBInk on the Kindle. The extension searches the usual
   `/mnt/us/extensions/FBInk/bin/` locations; alternatively set `FBINK_PATH` in
   `config.sh`.
   Dashboard bundles the matching PW2 `fbdepth` binary used for rotation; the
   PW2 build is the correct package directory for a Paperwhite 3.
2. Copy the entire `dashboard` directory to
   `/mnt/us/extensions/dashboard` on the Kindle.
3. Edit `config.sh` with your location, coordinates, timezone, and units.
4. Safely eject the Kindle, open KUAL, and choose **Dashboard -> Start
   Dashboard (Sleep + Auto Refresh)**.

The default location is Ithaca, New York. Open-Meteo does not require an API key.

## Desktop preview

Open `preview.html` in a desktop browser. It renders a 1448 x 1072 PW3 landscape screen
and fetches the same live Ithaca forecast used by the Kindle. This preview is
for development only and does not need to be copied to the Kindle.

## Quotes

Edit `data/quotes.txt` to customize the bundled rotation. Each line uses:

```text
Quote text|Author
```

Both the preview and Kindle fetch
https://raw.githubusercontent.com/ddeepak95/kindle-eink-dashboard/main/data/quotes.txt
by default. Edit that file in GitHub to update the daily rotation. Failed requests
preserve the last downloaded quotes; a bundled quote remains available before the
first successful download. The Kindle also accepts a custom two-line quote/author
file through QUOTE_URL. Set QUOTE_URL="" to use only bundled quotes on the Kindle.

Set `SHOW_QUOTE="0"` for a weather-only dashboard.

## Network behavior

By default, the extension uses the Kindle's current Wi-Fi state and does not
change it. Set `MANAGE_WIFI="1"` to turn Wi-Fi on before a request and off when
the request finishes. That option is most useful once suspend/wake automation
is added.

Logs and cached responses live in `cache/`. If a refresh fails but an older
forecast exists, the dashboard renders the older forecast instead of showing a
blank screen.

## Troubleshooting

- **FBInk was not found:** install a Kindle build of FBInk or set its exact path
  in `config.sh`.
- **No weather data:** confirm Wi-Fi is connected and that the Kindle's clock is
  correct; old clocks commonly break HTTPS certificate validation.
- **Small/blocky type:** the installed FBInk build lacks OpenType support or the
  configured Kindle fonts were not found, so the safe bitmap fallback was used.
- Review `cache/dashboard.log` for fetch and render events.

## Forecast grouping

Adjacent hours share a period when their weather codes match (clear and mostly
clear may merge), the entire temperature range is at most 3 degrees, and rain
probability varies by at most 20 percentage points without crossing 50%.
Rain intensity changes, rain starting/stopping, snow and storms create separate
periods. Each period shows the temperature range and highest rain probability.
The next 12 forecast hours start at the next full hour, excluding the current hour,
with precipitation emphasized (for example, at 1:30 PM: 2 PM through 1 AM).

Run node tests/dashboard.test.cjs to check preview/Kindle grouping parity and
quote parsing. These checks require Bash (Git for Windows is supported).
When more than six distinct periods remain, the forecast uses two rows.
