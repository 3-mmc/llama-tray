# LlamaTray

A Windows system-tray monitor for [llama-swap](https://github.com/mostlygeek/llama-swap),
written in [Xojo](https://xojo.com). It shows which model holds the GPU and lets you
load, unload or restart models without opening the web UI.

- **Icon colour:** grey when nothing is loaded, green when a model is ready, orange while
  one is starting or stopping, red when the gateway is unreachable. A white bar inside the
  disc shows VRAM use.
- **Tooltip:** running models and VRAM (`used / total GB`).
- **Click:** a menu to unload each running model or all of them, load any configured model
  (aliases are hidden), open the llama-swap UI, restart the gateway, or quit.
- **Double-click:** opens the llama-swap UI.

It polls `GET /running` every 3 s, `GET /v1/models` every 30 s, and
`nvidia-smi --query-gpu=memory.used,memory.total` for VRAM.

## Assumptions to adjust

These are hard-coded in `App.xojo_code`:

| What | Value | Where |
|---|---|---|
| Gateway URL | `http://127.0.0.1:9292` | constant `kBase` |
| Restart command | `D:\llama-swap\gateway.ps1 stop`, then `start` | `RestartGateway` |
| Poll interval | 3000 ms | constant `kPollMs` |

llama-swap (tested with v262) has no "load" endpoint. **Load** sends
`GET /upstream/<model>/`, which starts the model as a side effect. **Unload** uses
`POST /api/models/unload/<model>`.

## Building

The project is saved in Xojo's text format (`.xojo_project`), so it diffs cleanly.
Open it in Xojo 2026r2 or later and build for Windows 64-bit. A Xojo licence is
needed to build standalone executables.

`tools/xojo-ide` is a small Python script that drives the Xojo IDE's
[IDE Communicator](https://documentation.xojo.com/topics/build_automation/ide_communicator.html)
from WSL, so builds can be scripted from the command line:

```sh
tools/xojo-ide build 'D:\path\to\LlamaTray.xojo_project'
```

On Windows the communicator is a TCP listener on `127.0.0.1`, not the named pipe the docs
suggest. The IDE also builds from its in-memory copy of the project and ignores edits made
on disk. To pick them up, `build` quits the IDE (discarding unsaved changes), reopens the
project, then builds.

To start LlamaTray at logon, put a shortcut to the built `LlamaTray.exe` in `shell:startup`.

## Licence

MIT
