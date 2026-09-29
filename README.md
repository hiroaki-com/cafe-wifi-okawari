# cafe-wifi-okawari

[![test](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml/badge.svg)](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-lightgrey)

English | [日本語](README.ja.md)

Automatically re-accepts the captive portal terms when a free café Wi‑Fi in Japan sends you back to its login page after the time limit (e.g. 60 minutes). *Okawari* means "a refill" — like a coffee refill, but for Wi‑Fi.

- On Wi2 Wi‑Fi where you have accepted the terms yourself, checks every 10 seconds, so it notices a logout within about 10 seconds and usually re-authenticates a few seconds later
- Works with any time limit — it reacts to the login page, not a timer
- No IDs, passwords, or email addresses. Nothing secret is stored
- Nothing extra to install: runs on the zsh, curl, and launchd that ship with macOS

## Supported networks

Free Wi‑Fi from Wire and Wireless (Wi2) where you only need to accept the terms.

| Shop | SSID | Status |
|---|---|---|
| Doutor / Excelsior Caffé | `DOUTOR_FREE_Wi-Fi` | Tested (recording your acceptance and automatic re-acceptance after the time limit each confirmed at one shop) |
| Starbucks | `at_STARBUCKS_Wi2` | Expected to work (same portal) |
| Tully's Coffee | `tullys_Wi-Fi` | Expected to work (same portal) |
| Skylark group (Gusto, etc.) | `.Wi2_Free_at_【SK.GROUP】` | Expected to work (same portal) |
| Renoir / Miyama Coffee | `Renoir_Miyama_Wi-Fi` | Expected to work (same portal). The 3-hour daily cap cannot be extended |

Networks that need a sign-up, an email address, or a survey (McDonald's, Saizeriya, etc.) are out of scope. See [DESIGN.md](DESIGN.md) (Japanese) for the survey.

## Requirements

macOS 15 or later (uses the built-in `/usr/bin/jq`). Apple silicon and Intel. Tested on macOS 27.

## Before you use it

This is an unofficial tool that automates reconnecting to free Wi‑Fi that you yourself are allowed to use. It is not endorsed or recommended by Wi2 or any shop, and the author has not obtained Wi2's permission for automatic re-acceptance. The table above shows technical test results and expectations; it does not mean automated use is permitted.

### When you may use it

- Check the current terms of the Wi‑Fi you use (for Wi2, the [Free Wi‑Fi Service Terms](https://wi2.co.jp/rules/free-wifi.html), in Japanese), its connection conditions, and the shop's rules, and use the tool only within what you are allowed to do.
- Being allowed to reconnect as often as you like is not the same as being allowed to automate it. If it is unclear whether automated use, or connecting without going through the login page, is allowed, use the normal login page until you have confirmed it with the provider.
- Do not use it to get around required steps such as time or usage limits, suspensions, identity checks, sign-ups, or surveys. The tool does not count usage time or reconnections. Check the notices in the shop too (for example, Doutor's [flyer](https://www.doutor.co.jp/dcs/service/images/doutor_free_wi-fi.pdf) says "60min three times per day" in English, while the Japanese text only says you can re-authenticate after 60 minutes).
- Stop using it if the shop or the provider asks you to. Even when Wi‑Fi can be reconnected, the shop's own rules, such as how long you may stay, still apply.

### About automatic acceptance

Accept the terms yourself on the login page the first time. The tool infers that you accepted from the connection state and records that network: macOS keeps a Wi‑Fi with a login page unusable until you accept, and the tool never sends an acceptance on a network it has not recorded, so a Wi2 network that works means you accepted (the same applies when the tool sees the login page first and the connection then comes back). After that, it does not show the terms page; it sends the acceptance again directly to the authentication API (the same request as the login page's "accept" button). Notices shown on the login page are not displayed either. Use the tool only if you understand this and want automatic re-acceptance.

The tool does not verify your act of accepting, and it does not detect changes to the terms. Because it skips the terms page, it cannot see a notice of changes shown there. Network identification is also limited, so it cannot guarantee a manual first acceptance at every shop (at another shop of the same brand, it may send the acceptance without one). If you learn that the terms have changed or new conditions apply, stop the tool and do not resume automatic reconnection until you have reviewed them.

### When to stop it

The tool cannot tell a refusal due to a usage cap or suspension from a temporary network problem. If the auth server refuses the acceptance three times in a row on the same network and the connection does not come back, the tool stops re-accepting on that network and tells you in a dialog (accept on the login page yourself to resume). On timeouts and server errors it does not stop; it keeps retrying with a growing interval (up to 30 minutes). If a cap or suspension is shown, or failures continue, stop automatic reconnection and check the normal login page.

Run `./install.sh uninstall` in the repository directory to stop and remove the background job, together with the list of recorded networks.

The license of this tool does not grant any right to use a Wi‑Fi service, nor permission for any action that violates the provider's terms.

## Install

```sh
git clone https://github.com/hiroaki-com/cafe-wifi-okawari.git
cd cafe-wifi-okawari
./install.sh
```

No `sudo`. The installer copies the script to `~/.local/bin/cafe-wifi-okawari` and registers a user LaunchAgent. Run `./install.sh` again to update.

## Usage

**Accept the terms yourself the first time.** On a network it has not recorded, the tool sends no acceptance. When you join, macOS opens the login window; read the terms and accept them yourself. Once the connection works, the tool records the network (`consent recorded … (online)` in the log). From the next time-out on, it re-accepts for you.

- If the tool first sees the login page at a time-out (for example on a Wi2 network it could not recognise when you joined), it sends nothing and shows a dialog once asking you to accept yourself. Reconnect to the Wi‑Fi, or open `http://captive.apple.com` in a browser, to get the login page.
- Networks are identified by the router's MAC address together with the brand (e.g. `doutor`). On a network not yet recorded, it waits for your manual acceptance. It cannot guarantee to tell shops apart, though (shops of the same brand may share the same value).
- It recognises Wi2 networks from the domain name handed out by the network (`wi2.ne.jp`), without sending anything. On other networks (e.g. at home) it only checks for a login page at Apple's `captive.apple.com` during the first 5 minutes after joining, as macOS itself does, and sends nothing to Wi2.

Messages are shown as dialogs that close by themselves after 2 minutes (macOS does not show notifications from background jobs). They and the installer messages follow your macOS language (Japanese or English).

## Uninstall

```sh
./install.sh uninstall
```

This also removes the list of networks you accepted. The log at `~/Library/Logs/cafe-wifi-okawari.log` is kept.

## Troubleshooting

Is it running? This shows whether it is registered, the brands of the networks you accepted, and the last 5 log lines (exits with 1 if it is not registered):

```sh
./install.sh status
```

The log is written only when something happens:

```sh
tail ~/Library/Logs/cafe-wifi-okawari.log
```

| Log line | Meaning |
|---|---|
| `consent recorded net=… (online)` | The Wi2 network worked although the tool had sent nothing, so it recorded that you accepted on the login page. It will re-accept automatically from now on |
| `consent recorded net=…` | You accepted after the tool had seen the login page; recorded as above |
| `consent pending net=…` | The tool saw the login page on a network it has not recorded. It waits for you to accept yourself |
| `re-authenticated api=ok probe=ok net=… t=Ns` | Reconnected automatically (the connection came back N seconds after it started sending the acceptance) |
| `network changed net=…` | The Mac switched to another network (e.g. tethering) during a re-authentication or a brand check. That attempt counts as neither a success nor a failure, and nothing is recorded as accepted |
| `login failed xN api=ng probe=ok` | The tool's attempt failed, but the connection came back another way (e.g. the macOS login window) |
| `login failed xN api=… probe=ng` | Could not reconnect. You get a dialog. Also happens when a daily cap (e.g. Renoir) is reached |
| `auto stopped net=… rejected x3` | The auth server refused the acceptance three times in a row, so automatic re-acceptance on this network was stopped (possibly a usage cap, a suspension, or changed conditions). You get a dialog. Check the login page; accepting yourself resumes it |
| `redirect failed xN curl=… http=…` | Could not reach the auth server (timeout or outage). No dialog |
| `redirect failed xN http=… to=…` / `no session_id` | Unexpected response from the auth server (the portal may have changed). You get a dialog on a recorded network |
| `portal unknown xN` | A Wi2 or recorded network showed a login page that is not Wi2's. The tool sends nothing |
| `portal mismatch xN mac=… ip=…` | The login page was for a different device (MAC or IP address not this Mac's), so the tool sent nothing |
| `not free wi-fi xN` | A Wi2 network that is not a free "accept the terms" Wi‑Fi. The tool does nothing there |
| `probe failed xN net=… curl=… http=…` | On a Wi2, recorded, or pending network, the connection state could not be checked (non-zero `curl` means a network error; `http` is an unexpected response). The tool sends nothing |

On repeated failures the retry interval backs off from 30 seconds up to 30 minutes, every failure is logged (failed status checks only on the 1st, 2nd, 4th, 8th…), and you get a single dialog (plus one more if it stops after repeated refusals). Moving to another shop resets the backoff.

## Notes

- **VPN / iCloud Private Relay** can prevent the tool from detecting the login page.
- **Free Wi‑Fi is unencrypted.** This tool only reconnects; protect your traffic with HTTPS or a VPN.
- **Terms of use.** After your first manual acceptance, the tool sends the acceptance directly to the authentication API without showing the terms page. It has no way to lift server-side time or usage limits, and it does not spoof MAC addresses or open multiple sessions. Read [Before you use it](#before-you-use-it) first.
- Unofficial and not affiliated with any of the companies above. It may break if a portal changes. How it relates to the terms and the law is reviewed in [DESIGN.md](DESIGN.md) §4 (Japanese).

## Development

```sh
zsh test/run.sh   # branch tests with mocked curl, launchctl, etc. (no real network access)
```

Design notes, security model, and verification status: [DESIGN.md](DESIGN.md) (Japanese).

## License

[MIT](LICENSE)
