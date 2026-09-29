# cafe-wifi-okawari

[![test](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml/badge.svg)](https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-lightgrey)

English | [日本語](README.ja.md)

Automatically re-accepts the captive portal terms when a free café Wi‑Fi in Japan sends you back to its login page after the time limit (e.g. 60 minutes). *Okawari* means "a refill" — like a coffee refill, but for Wi‑Fi.

- On Wi2 Wi‑Fi where you have accepted the terms yourself, it checks every 10 seconds, notices a logout within about 10 seconds, and usually reconnects a few seconds later (your connection is down in between; see [Caveats](#caveats))
- Works with any time limit — it reacts to the login page, not a timer
- Uses no IDs, passwords, or email addresses, and stores nothing secret
- Nothing extra to install: it runs on the zsh, curl, and launchd that ship with macOS

## Supported networks

Free Wi‑Fi from Wire and Wireless (Wi2) where you only need to accept the terms.

| Shop | SSID | Status |
|---|---|---|
| Doutor / Excelsior Caffé | `DOUTOR_FREE_Wi-Fi` | Tested (recording your acceptance and automatic re-acceptance after the time limit each confirmed at one shop) |
| Skylark group (Gusto, etc.) | `.Wi2_Free_at_【SK.GROUP】` | Tested (recording your acceptance and automatic re-acceptance after the time limit each confirmed at one shop) |
| Starbucks | `at_STARBUCKS_Wi2` | Expected to work (same portal) |
| Tully's Coffee | `tullys_Wi-Fi` | Expected to work (same portal) |
| Renoir / Miyama Coffee | `Renoir_Miyama_Wi-Fi` | Expected to work (same portal). The 3-hour daily cap cannot be extended |

Networks that need a sign-up, an email address, or a survey (McDonald's, Saizeriya, etc.) are not supported. The survey is in [DESIGN.md](DESIGN.md) (Japanese).

## Requirements

macOS 15 or later (uses the built-in `/usr/bin/jq`). Apple silicon and Intel. Tested on macOS 27.

## Install and use

> Before installing, please read [Before you use it](#before-you-use-it). It explains the conditions of use and how the tool re-sends your acceptance automatically.

### 1. Install

Run this in Terminal:

```sh
git clone https://github.com/hiroaki-com/cafe-wifi-okawari.git
cd cafe-wifi-okawari
./install.sh
```

No `sudo` needed. The installer copies the script to `~/.local/bin/cafe-wifi-okawari` and registers a user LaunchAgent. From then on it runs in the background every 10 seconds, so you can close Terminal. After a restart, it starts again automatically when you log in.

### 2. Accept the terms yourself once at the shop

When you join the shop's Wi‑Fi (e.g. `DOUTOR_FREE_Wi-Fi`), macOS opens its login window. Please read the terms and press "accept" as usual.

Once the connection works, the tool records the shop as one where you accepted the terms yourself. You can check this with `./install.sh status` (see below). If you had already accepted at the shop before installing, it is recorded right after installation.

### 3. Keep using the Wi‑Fi

There is nothing else to do. At each time-out (about 60 minutes at Doutor), the tool accepts the terms again for you.

```text
You accept (first time only)
  → about 60 minutes later, the session times out: you are sent back to the login page and the connection stops
  → the tool notices (within 10 seconds)
  → it re-sends the acceptance; the connection comes back a few seconds later
  → the same happens at every time-out
```

A successful reconnection shows nothing. What can happen while the connection is down is described in [Caveats](#caveats).

### Check that it is working

```sh
./install.sh status
```

You will see something like this. "Current network" tells whether the network you are on now is one you accepted (the tool identifies a network by its gateway's MAC address). "Last auth" is when your own acceptance was recorded or the tool last re-accepted, and "Next time-out" is an estimate based on it:

```text
Service          loaded (LaunchAgent local.cafe-wifi-okawari)
Schedule         every 10 s, and whenever the network settings change
Program          /Users/you/.local/bin/cafe-wifi-okawari
Last exit code   0 (412 runs since loaded)
Current network  gateway 0:0:5e:0:1:46 (doutor), accepted: auto re-authentication on
Accepted         1 network (brand: doutor)
Last auth        2026-10-01 10:05:12 (12 min ago), consent recorded on doutor
Next time-out    around 11:05, in 47 min (if the shop's limit is 60 minutes)
Log              /Users/you/Library/Logs/cafe-wifi-okawari.log (1 line)

Recent log:
  2026-10-01 10:05:12 consent recorded net=… doutor (online)
```

What each log line means is listed in [Troubleshooting](#troubleshooting).

### Common situations

- **You go to another shop**: when the login window appears after you join, accept the terms yourself, as in step 2
- **A dialog asks you to accept the terms yourself once**: the session timed out at a shop the tool has not recorded. It sent nothing, so please accept on the login page yourself. To get the login page, reconnect to the Wi‑Fi or open `http://captive.apple.com` in a browser
- **A dialog says it could not reconnect, or that it stopped reconnecting**: please check the login page in the same way and accept yourself if needed. The log tells you why ([Troubleshooting](#troubleshooting))
- **You want to update**: run `git pull` in the repository directory, then `./install.sh` again
- **You want to stop using it**: run `./install.sh uninstall` ([Uninstall](#uninstall))

### How it works

- Networks are identified by the router's MAC address together with the brand (e.g. `doutor`). Shops of the same brand may share the same value, so it cannot always tell shops apart.
- It recognises Wi2 networks from the domain name handed out by the network (`wi2.ne.jp`), without sending anything. On other networks (e.g. at home) it only checks for a login page at Apple's `captive.apple.com` during the first 5 minutes after joining, as macOS itself does, and sends nothing to Wi2.
- Dialogs follow your macOS language (Japanese or English). Messages from `install.sh` are in English.

## Before you use it

This is an unofficial tool that automates reconnecting to free Wi‑Fi that you yourself are allowed to use. It is not endorsed or recommended by Wi2 or any shop, and the author has not obtained Wi2's permission for automatic re-acceptance. The table above shows technical test results and expectations; it does not mean automated use is permitted.

### When you may use it

- Check the current terms of the Wi‑Fi you use (for Wi2, the [Free Wi‑Fi Service Terms](https://wi2.co.jp/rules/free-wifi.html), in Japanese), its connection conditions, and the shop's rules, and use the tool only within what you are allowed to do.
- Being allowed to reconnect as often as you like is not the same as being allowed to automate it. If it is unclear whether automated use, or connecting without going through the login page, is allowed, please use the normal login page until you have confirmed it with the provider.
- Do not use it to get around required steps such as time or usage limits, suspensions, identity checks, sign-ups, or surveys. The tool does not count usage time or reconnections. Please check the notices in the shop too (for example, Doutor's [flyer](https://www.doutor.co.jp/dcs/service/images/doutor_free_wi-fi.pdf) says "60min three times per day" in English, while the Japanese text only says you can re-authenticate after 60 minutes).
- Stop using it if the shop or the provider asks you to. Even when Wi‑Fi can be reconnected, the shop's own rules, such as how long you may stay, still apply.

### About automatic acceptance

Please accept the terms yourself on the login page the first time. macOS keeps a Wi‑Fi with a login page unusable until you accept, and the tool never sends an acceptance on a network it has not recorded. So when a Wi2 network works (or the connection comes back after the tool saw the login page), the tool infers that you accepted and records that network. At later time-outs it does not show the terms page; it sends the acceptance directly to the authentication API (the same request as the login page's "accept" button). Notices shown on the login page are not displayed either. Please use the tool only if you understand this and want automatic re-acceptance.

The tool does not verify your act of accepting, and it does not detect changes to the terms. Because it skips the terms page, it cannot see a notice of changes shown there. Network identification is also limited, so it cannot guarantee a manual first acceptance at every shop (at another shop of the same brand, it may send the acceptance without one). If you learn that the terms have changed or new conditions apply, stop the tool and do not resume automatic reconnection until you have reviewed them.

### When to stop it

The tool cannot tell a refusal due to a usage cap or suspension from a temporary network problem. If the auth server refuses the acceptance three times in a row on the same network and the connection does not come back, the tool stops re-accepting on that network and tells you in a dialog (accept on the login page yourself to resume). On timeouts and server errors it does not stop; it keeps retrying with a growing interval (up to 30 minutes). If a cap or suspension is shown, or failures continue, stop automatic reconnection and check the normal login page.

Run `./install.sh uninstall` in the repository directory to remove the background job and the list of recorded networks.

The license of this tool does not grant any right to use a Wi‑Fi service, nor permission for any action that violates the provider's terms.

## Caveats

### Each time-out briefly interrupts your connection

At each time-out (at Doutor, about 60 minutes after you accept or the tool re-authenticates), your connection is down until re-authentication completes: up to 10 seconds for the tool to notice, plus a few seconds after it sends the acceptance (measured: about 6 seconds at Gusto with the current version; about 21 seconds at Doutor with an earlier version that checked every 30 seconds).

The Wi‑Fi stays connected and your IP address does not change. Many apps carry on once the connection is back, but the effect of the gap varies by app. For example:

- **Video calls and online meetings**: video or audio may freeze or show "reconnecting". You may be dropped from the call
- **Screen sharing and live streaming**: what others see stops. A stream may end
- **Large uploads and downloads**: may fail (apps that cannot resume start over)
- **SSH, remote desktop, online games**: the session may disconnect

Before an important call, stream, or presentation, please check the next time-out with `./install.sh status` and plan around it, or use another connection such as tethering. The tool re-authenticates only after a time-out; it does not renew ahead of time.

### Dialogs appear only when you are offline

A successful reconnection shows nothing (it is only logged; see `./install.sh status`), so the tool does not interrupt your screen every hour. A dialog appears only in these cases, all of them while you have no internet connection:

- You need to accept the terms yourself the first time
- Automatic reconnection failed (once while failures continue)
- The login was refused repeatedly and automatic re-acceptance was stopped

Dialogs appear in the middle of the screen and close by themselves after 2 minutes. macOS does not show notifications from background jobs, so the usual top-right notifications are not available. Because they are not notifications, Focus modes (such as Do Not Disturb) do not hold them back, and they show up in screen sharing and screen recordings.

### When it cannot reconnect for you

- **Rejoining the Wi‑Fi after a time-out** (waking from sleep, losing the signal, turning Wi‑Fi off and on): macOS opens its login window and keeps other apps off that Wi‑Fi until you accept, so the tool cannot help. Please accept in the login window yourself. It reconnects automatically again from the next time-out (this acceptance is not logged, so the estimate in `./install.sh status` does not include it)
- **While the Mac sleeps**: the tool does not run. If the session has timed out when the Mac wakes and the Wi‑Fi is still connected, it re-authenticates within about 10 seconds
- **When a daily usage cap is reached** (e.g. Renoir): re-authentication is refused and the connection does not come back
- **VPN / iCloud Private Relay** can prevent the tool from detecting the login page

### Other notes

- **Free Wi‑Fi is unencrypted.** This tool only reconnects; please protect your traffic with HTTPS or a VPN.
- **Terms of use.** The tool has no way to lift server-side time or usage limits, and it does not spoof MAC addresses or open multiple sessions. For how it re-sends the acceptance without showing the terms page, please read [Before you use it](#before-you-use-it).
- Unofficial and not affiliated with any of the companies above. It may break if a portal changes. How it relates to the terms and the law is reviewed in [DESIGN.md](DESIGN.md) §4 (Japanese).

## Uninstall

```sh
./install.sh uninstall
```

This also removes the list of networks you accepted. The log at `~/Library/Logs/cafe-wifi-okawari.log` is kept; delete it by hand if you no longer need it.

## Troubleshooting

To check that it is running (shows whether it is registered and its last exit code, whether the current network is one you accepted, the brands of the networks you accepted, when it last authenticated and the estimated next time-out, and the last 5 log lines; it sends nothing over the network, and exits with 1 if it is not registered):

```sh
./install.sh status
```

The log is written only when something happens:

```sh
tail ~/Library/Logs/cafe-wifi-okawari.log
```

| Log line | Meaning |
|---|---|
| `consent recorded net=… (online)` | The Wi2 network worked although the tool had sent nothing, so it recorded that you accepted on the login page. It re-accepts automatically from the next time-out |
| `consent recorded net=…` | You accepted after the tool had seen the login page; recorded as above |
| `consent pending net=…` | The tool saw the login page on a network it has not recorded, and is waiting for you to accept yourself |
| `re-authenticated api=ok probe=ok net=… t=Ns` | Reconnected automatically (the connection came back N seconds after the tool started sending the acceptance) |
| `network changed net=…` | The Mac switched to another network (e.g. tethering) during a re-authentication or a brand check. That attempt counts as neither a success nor a failure, and nothing is recorded as accepted |
| `login failed xN api=ng probe=ok` | The tool's attempt failed, but the connection came back another way (e.g. the macOS login window) |
| `login failed xN api=… probe=ng` | Could not reconnect. You get a dialog. This also happens when a daily cap (e.g. Renoir) is reached |
| `auto stopped net=… rejected x3` | The auth server refused the acceptance three times in a row, so automatic re-acceptance on this network was stopped (possibly a usage cap, a suspension, or changed conditions). You get a dialog. Check the login page; accepting yourself resumes it |
| `redirect failed xN curl=… http=…` | Could not reach the auth server (timeout or outage). No dialog |
| `redirect failed xN http=… to=…` / `no session_id` | Unexpected response from the auth server (the portal may have changed). You get a dialog on a recorded network |
| `portal unknown xN` | A Wi2 or recorded network showed a login page that is not Wi2's. The tool sends nothing |
| `portal mismatch xN mac=… ip=…` | The login page was for a different device (MAC or IP address not this Mac's), so the tool sent nothing |
| `not free wi-fi xN` | A Wi2 network that is not a free "accept the terms" Wi‑Fi. The tool does nothing there |
| `probe failed xN net=… curl=… http=…` | On a Wi2, recorded, or pending network, the connection state could not be checked (non-zero `curl` means a network error; `http` is an unexpected response). The tool sends nothing |

On repeated failures, the retry interval backs off from 30 seconds up to 30 minutes. Every failure is logged (failed status checks only on the 1st, 2nd, 4th, 8th…), and you get a single dialog (plus one more if it stops after repeated refusals). Moving to another shop resets the backoff.

## Development

```sh
zsh test/run.sh   # branch tests with mocked curl, launchctl, etc. (no real network access)
```

Design notes, security model, and verification status: [DESIGN.md](DESIGN.md) (Japanese).

## License

[MIT](LICENSE)
