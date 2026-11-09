# Independent CLI installation

Run `bash install-cli.sh --version X.Y.Z` to ensure a minimum released CLI version.
The default preserves an existing native/npm installation method and accepts a
newer installed version. A missing CLI or a legacy plugin launcher selects native.
Use `--method npm` when the user's environment requires Node-based execution.
An npm error does not silently switch to native.

Fresh native installation verifies the release checksum and executable version before
atomically installing at `~/.local/bin/clay`. Existing native CLIs update through
their own `clay update` command only when below the minimum, including installations
outside PATH. The resulting version must meet the minimum. No sudo is used. Existing
npm installations are updated through npm.
Unrecognized files are not overwritten. Credentials and configuration are untouched.
The installer reports PATH changes needed; the CLI setup skill owns persistent shell
configuration and verifies the command from the agent's shell.

Tests run in the CLI Jest suite with isolated homes and mocked download/package
manager commands; they do not install software in the developer's home.

`check-cli.sh` is a local session-start check. It reads `../cli-min-version`, detects
legacy launchers before executing them, and bounds `--version` execution. It emits
readiness guidance in Claude Code/Codex or Cursor hook format, or plain text for skills.
It never installs, authenticates, or checks remote releases. Hosts without hook support
use the same check from the entry skill.
