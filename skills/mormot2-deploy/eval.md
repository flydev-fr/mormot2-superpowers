```yaml
positive:
  - prompt: "Bundle SQLite static so we ship a single binary"
    expected: mormot2-deploy
  - prompt: "Install our REST server as a Windows service"
    expected: mormot2-deploy
  - prompt: "Front the server with nginx as a reverse proxy with WebSocket support"
    expected: mormot2-deploy
  - prompt: "Write a systemd unit for the API daemon"
    expected: mormot2-deploy

negative:
  - prompt: "Switch our HTTP server to async mode with TLS via ACME"
    must_not_trigger: mormot2-deploy
    expected: mormot2-net
  - prompt: "Add a search path for mORMot 2 sources to the dproj"
    must_not_trigger: mormot2-deploy
    expected: delphi-build
```
