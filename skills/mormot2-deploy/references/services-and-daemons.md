# Services and daemons

mORMot 2 has three layers for "run this binary unattended". Pick the one that matches the OS you are deploying to.

| Layer                       | Unit                  | Use when                                                                                  |
|-----------------------------|-----------------------|-------------------------------------------------------------------------------------------|
| `TSynDaemon`                | `mormot.app.daemon`   | Cross-platform shape: same code installs as Windows Service or runs as POSIX daemon.      |
| `TServiceController` / `TServiceSingle` | `mormot.core.os` | Direct Windows Service Control Manager calls, or installer code that registers services. |
| `TSynAngelize`              | `mormot.app.agl`      | Supervising N child processes with health checks, restart, log redirection.               |

## Inside `TSynDaemon`

`TSynDaemon` (subclass `TSynPersistent`) wraps both worlds. On Windows, `CommandLine` recognizes `/install`, `/uninstall`, `/start`, `/stop`, `/state`, `/console`, `/version`, `/help`. On POSIX, it recognizes `--run`, `--fork`, `--kill`, `--state`, `--console`, `--help`. The same binary serves both.

```pascal
type
  TMyDaemon = class(TSynDaemon)
  public
    procedure Start; override;
    procedure Stop; override;
  end;

procedure TMyDaemon.Start;
begin
  // Bring up your REST server, workers, scheduled jobs.
end;

procedure TMyDaemon.Stop;
begin
  // Tear down in reverse order. Must be safe to call multiple times.
end;

begin
  with TMyDaemon.Create(TSynDaemonSettings, '', '', '') do
  try
    CommandLine; // dispatches to Start/Stop based on platform-specific switch
  finally
    Free;
  end;
end.
```

`TSynDaemonSettings` is a JSON file (`<exename>.settings`) that the daemon reads at startup. The fields used at deploy time:

- `ServiceName`, `ServiceDisplayName` - identifiers passed to the SCM on Windows install
- `Log` - set of `TSynLogLevel`; default is `LOG_STACKTRACE + [sllNewRun]`
- `LogPath` - directory for `TSynLog` output; defaults to exe folder (Windows) or `/var/log` (POSIX)
- `LogRotateFileCount` - default 2 (rotates by 20 MB once exceeded)

INI is accepted as a fallback if the JSON file is missing.

## Windows Service: from `TSynDaemon` to `TServiceController.Install`

`myserver.exe /install` is the user-facing path. From an installer (Inno Setup, WiX, MSI custom action), drive `TServiceController.Install` directly:

```pascal
TServiceController.Install(
  'MyService',                     // SCM internal name
  'My Application Service',        // display name in services.msc
  'REST API for MyApp',            // description
  {AutoStart=}true,
  {ExeName=}'',                    // '' = current ParamStr(0); pass full path otherwise
  {Dependencies=}'Tcpip;');        // ; or # separated list
```

For "what is the service doing right now", use `TServiceController.CurrentState('MyService')`. It returns `ssRunning`, `ssStopped`, `ssStartPending`, `ssStopPending`, `ssPaused`, `ssNotInstalled`, or `ssErrorRetrievingState`.

`TServiceSingle` is the in-process counterpart used when the binary IS the service. `TSynDaemon.CommandLine` instantiates `TServiceSingle` and calls `ServiceSingleRun` to hand control to the SCM dispatcher. Reach for `TServiceSingle` directly only when bypassing `TSynDaemon`.

## systemd unit

Recommended template for a `TSynDaemon` running with `--run` on Linux:

```ini
# /etc/systemd/system/myserver.service
[Unit]
Description=MyApp REST server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=mormot
Group=mormot
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/bin/myserver --run
Restart=on-failure
RestartSec=5s

# Hardening (drop if your binary needs them).
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/myapp /var/lib/myapp

# Resource limits.
LimitNOFILE=65536
TasksMax=1024

[Install]
WantedBy=multi-user.target
```

Three deployment-time gotchas:

1. `Type=simple` is right for `--run`; `Type=forking` is right only for `--fork`. Mix them up and `systemctl status` reports "active (exited)" while the daemon is still running detached.
2. `ReadWritePaths=` MUST include every directory the daemon writes (logs, the SQLite file, any cache). Without it, `ProtectSystem=strict` makes those writes silently fail under newer systemd; the daemon logs nothing and serves stale data.
3. `User=mormot` only works if `/etc/myserver.settings` is readable by `mormot:mormot`. Run `chown mormot:mormot /etc/myserver.settings && chmod 0640` after install.

Reload after editing: `systemctl daemon-reload && systemctl enable --now myserver`.

## launchd plist (macOS)

For a daemon (system-wide) put the plist at `/Library/LaunchDaemons/com.example.myserver.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>com.example.myserver</string>
    <key>ProgramArguments</key>
    <array>
      <string>/opt/myapp/bin/myserver</string>
      <string>--run</string>
    </array>
    <key>WorkingDirectory</key> <string>/opt/myapp</string>
    <key>UserName</key>         <string>_mormot</string>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>StandardOutPath</key>  <string>/var/log/myapp/stdout.log</string>
    <key>StandardErrorPath</key><string>/var/log/myapp/stderr.log</string>
</dict>
</plist>
```

Permissions matter: `chown root:wheel /Library/LaunchDaemons/com.example.myserver.plist && chmod 644`. Load with `launchctl bootstrap system /Library/LaunchDaemons/com.example.myserver.plist`. macOS dylib loading is finicky, so prefer `OPENSSLSTATIC` here unless you ship the OpenSSL dylibs alongside the binary.

## `TSynAngelize` (process supervisor)

When the deploy unit is multiple processes (web + worker + scheduler) on one host, `TSynAngelize` replaces both NSSM and a custom systemd dependency graph with one JSON file:

```json
{
  "Services": [
    {
      "Name": "api",
      "Run": "/opt/myapp/bin/myserver",
      "Start": [ "start:%run% --run" ],
      "Stop":  [ "stop:%run%" ],
      "Watch": [ "http://127.0.0.1:8080/health=200" ],
      "WatchDelaySec": 30,
      "RetryStableSec": 60,
      "AbortExitCodes": [ 2, 3 ],
      "Notify": "ops@example.com,%log%alerts.log"
    },
    {
      "Name": "worker",
      "Run": "/opt/myapp/bin/worker",
      "Start": [ "sleep:2000", "start:%run%" ],
      "Stop":  [ "stop:%run%" ]
    }
  ]
}
```

Action verbs accepted in `Start` / `Stop` / `Watch`: `start:`, `stop:`, `exec:`, `wait:`, `sleep:N`, `service:Name` (Windows SCM), `http://host/path[=200]`. The supervisor itself is a `TSynDaemon`, so the same `--run` / `/install` switches apply at the top level.

## Decision matrix

- One binary, Linux: systemd
- One binary, macOS: launchd
- One binary, Windows: `TSynDaemon` `/install`
- Multiple binaries on one host, any OS: `TSynAngelize`
- Container with one process per container: no daemonization at all; run in foreground (`--console` on POSIX, console mode on Windows containers) and let the container runtime handle restarts
