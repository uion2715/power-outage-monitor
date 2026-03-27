# Washington Power Outage Monitor

This monitor checks the live Washington outage page on `poweroutage.us` and flags whenever the number of customers out is `10,000` or higher.

## What it does

- Polls `https://poweroutage.us/area/state/washington`
- Extracts the current `Customers Out` total from the page HTML
- Prints a status line on every check
- Fires an alert when outages cross the threshold
- Fires another alert if the total changes while it remains above the threshold
- Saves the last seen count to `wa-monitor-state.json`
- Publishes a browser-readable status file to `app/status.json`
- Optionally posts alert JSON to a webhook URL

## App dashboard

The folder `app/` contains a shareable web dashboard:

- `app/index.html`
- `app/styles.css`
- `app/app.js`
- `app/status.json`

Open `app/index.html` in a browser to view the dashboard. Keep the watcher running so it refreshes `app/status.json` with live data.

## Run one check

```powershell
powershell -ExecutionPolicy Bypass -File .\power-outage-monitor\watch-wa-outages.ps1 -Once
```

## Watch continuously

```powershell
powershell -ExecutionPolicy Bypass -File .\power-outage-monitor\watch-wa-outages.ps1
```

## Change the polling interval

```powershell
powershell -ExecutionPolicy Bypass -File .\power-outage-monitor\watch-wa-outages.ps1 -IntervalSeconds 120
```

## Send alerts to a webhook

```powershell
powershell -ExecutionPolicy Bypass -File .\power-outage-monitor\watch-wa-outages.ps1 -WebhookUrl "https://example.com/webhook"
```

## Publish the app for other people

If you want other people to see the dashboard, host the `app` folder on a machine or web server that can serve static files while the watcher script keeps updating `status.json`.

Simple options:

- Put the `app` folder on a Windows machine and serve it with IIS or another static web server
- Sync or deploy the folder to an internal web host
- Use the watcher on one machine and copy `status.json` to a hosted location on a schedule

Because browsers often block direct scraping of `poweroutage.us`, the dashboard reads the locally published `status.json` instead of calling the source site directly.

## Deploy to GitHub Pages

This project now includes a GitHub Actions workflow at `power-outage-monitor/.github/workflows/deploy-pages.yml` that:

- runs every 15 minutes
- refreshes `app/status.json`
- deploys the `app` folder to GitHub Pages

To use it:

1. Put this project in a GitHub repository.
2. In GitHub, enable Pages and set the source to `GitHub Actions`.
3. Push the repository.
4. Run the `Deploy Washington Outage App` workflow once manually, or wait for the first scheduled run.

After that, GitHub Pages will host the dashboard on a public URL and the workflow will keep the published status file fresh.

## Notes about deployment

- The workflow uses PowerShell and `curl`, so it can run on GitHub-hosted Linux runners.
- GitHub scheduled workflows are not truly real-time. With the current setup, the public app updates about every 15 minutes.
- If you need faster than that, the next step would be a small hosted API or serverless function instead of scheduled static publishing.

## Notes

- Default threshold is `10,000`, but you can override it with `-Threshold`.
- The script depends on the current Washington page layout. If `poweroutage.us` changes the markup, the regex may need a quick update.
