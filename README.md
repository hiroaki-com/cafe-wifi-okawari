# cafe-wifi-okawari

[![test](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml/badge.svg)](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-lightgrey)

English | [日本語](README.ja.md)

Automatically re-accepts the captive portal terms when a free café Wi‑Fi in Japan sends you back to its login page after the time limit (e.g. 60 minutes). *Okawari* means "a refill" — like a coffee refill, but for Wi‑Fi.

- Checks every 30 seconds and re-authenticates within about 30 seconds of being logged out
- Works with any time limit — it reacts to the login page, not a timer
- No IDs, passwords, or email addresses. Nothing secret is stored
- Nothing extra to install: runs on the zsh, curl, and launchd that ship with macOS

## Supported networks

Free Wi‑Fi from Wire and Wireless (Wi2) where you only need to accept the terms.

| Shop | SSID | Status |
|---|---|---|
| Doutor / Excelsior Caffé | `DOUTOR_FREE_Wi-Fi` | Tested |
| Starbucks | `at_STARBUCKS_Wi2` | Expected to work (same portal) |
| Tully's Coffee | `tullys_Wi-Fi` | Expected to work (same portal) |
| Skylark group (Gusto, etc.) | `.Wi2_Free_at_【SK.GROUP】` | Expected to work (same portal) |
| Renoir / Miyama Coffee | `Renoir_Miyama_Wi-Fi` | Expected to work (same portal). The 3-hour daily cap cannot be extended |

Networks that need a sign-up, an email address, or a survey (McDonald's, Saizeriya, etc.) are out of scope. See [DESIGN.md](DESIGN.md) (Japanese) for the survey.

## Requirements

macOS 15 or later (uses the built-in `/usr/bin/jq`). Apple silicon and Intel. Tested on macOS 27.

## Install

```sh
git clone https://github.com/hiroaki-com/cafe-wifi-okawari.git
cd cafe-wifi-okawari
./install.sh
```

No `sudo`. The installer copies the script to `~/.local/bin/cafe-wifi-okawari` and registers a user LaunchAgent. Run `./install.sh` again to update.

## Usage

**Accept the terms yourself once per shop.** On a network it has not seen before, the tool sends nothing. Read the terms on the login page and accept them yourself; the tool notices and remembers that network. From the next time-out on, it re-accepts for you.

- If the login page comes back before the tool has learned the network, you get a one-time notification asking you to accept in the browser.
- Shops are identified by the MAC address of the router. A different branch of the same chain needs one manual acceptance again.

Notifications and installer messages follow your macOS language (Japanese or English).

## Uninstall

```sh
./install.sh uninstall
```

This also removes the list of networks you accepted. The log at `~/Library/Logs/cafe-wifi-okawari.log` is kept.

## Troubleshooting

Is it running?

```sh
launchctl print gui/$UID/local.cafe-wifi-okawari | grep -E 'state|last exit code'
```

The log is written only when something happens:

```sh
tail ~/Library/Logs/cafe-wifi-okawari.log
```

| Log line | Meaning |
|---|---|
| `consent recorded net=…` | You accepted on this network; it will be re-accepted automatically from now on |
| `re-authenticated api=ok probe=ok` | Reconnected automatically |
| `login failed xN api=ng probe=ok` | The tool's attempt failed, but the connection came back another way (e.g. the macOS login window) |
| `login failed xN api=ng probe=ng` | Could not reconnect. You get a notification. Also happens when a daily cap (e.g. Renoir) is reached |
| `redirect failed xN curl=… http=…` | Could not reach the auth server (timeout or outage). Can appear on non-Wi2 networks such as hotels; harmless. No notification |
| `redirect failed xN no session_id` | Unexpected response from the auth server (the portal may have changed). You get a notification |

On repeated failures the retry interval backs off from 30 seconds up to 30 minutes, the log is written on the 1st, 2nd, 4th, 8th… failure, and you get a single notification. Moving to another shop resets the backoff.

## Notes

- **VPN / iCloud Private Relay** can prevent the tool from detecting the login page.
- **Free Wi‑Fi is unencrypted.** This tool only reconnects; protect your traffic with HTTPS or a VPN.
- **Terms of use.** After your first manual acceptance, the tool presses the same "accept" button for you. It does not bypass time limits, spoof MAC addresses, or open multiple sessions. Follow each shop's terms.
- Unofficial and not affiliated with any of the companies above. It may break if a portal changes.

## Development

```sh
zsh test/run.sh   # branch tests with mocked curl, launchctl, etc. (no real network access)
```

Design notes, security model, and verification status: [DESIGN.md](DESIGN.md) (Japanese).

## License

[MIT](LICENSE)
