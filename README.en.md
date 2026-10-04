<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/icon/icon-white.png">
    <img src="assets/icon/icon.png" width="112" alt="">
  </picture>
</p>

<h1 align="center">cafe-wifi-okawari</h1>

<p align="center">
  <a href="https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml"><img src="https://github.com/hiroaki-com/cafe-wifi-okawari/actions/workflows/test.yml/badge.svg" alt="test"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-lightgrey" alt="macOS 15+">
</p>

<p align="center"><a href="README.md">日本語</a> | English</p>

A macOS tool that automatically re-accepts the terms and reconnects when a café's free Wi‑Fi session times out. It saves you from repeating the login steps, helping you stay focused on your work.

- Automatic reconnection — Accept the terms yourself the first time. The tool reconnects in the background at later time-outs.
- Status in the menu bar — Check the connection status from the coffee cup icon.
- Built with macOS tools — No extra software or administrator privileges required.

Your connection is briefly interrupted until reconnection completes. Check the [supported networks](#supported-networks) and [conditions of use](#before-you-use-it) before using the tool.

## Supported networks

Free Wi‑Fi from Wi2 and USEN (USPOT-02) where you only need to accept the terms.

| Shop | SSID | Status |
|---|---|---|
| Doutor / Excelsior Caffé | `DOUTOR_FREE_Wi-Fi` | Tested |
| Skylark group (Gusto, etc.) | `.Wi2_Free_at_【SK.GROUP】` | Tested |
| Tully's Coffee | `tullys_Wi-Fi` | Tested |
| Café de Crié | Not officially published | Tested |
| Starbucks | `at_STARBUCKS_Wi2` | Expected to work |
| Renoir / Miyama Coffee | `Renoir_Miyama_Wi-Fi` | Expected to work |
| Komeda's Coffee | `Komeda_Wi-Fi` | Not yet tested |

Tested networks have been checked at real shops for both recording the initial acceptance and reconnecting automatically after a time-out. Shop counts, test counts, and test conditions are in §7 of [DESIGN.md](DESIGN.md) (Japanese). "Expected to work" means the same portal as a tested shop; "Not yet tested" means the same system as Tully's but not yet tried at a real shop.

- Some Skylark brands have ended their Wi‑Fi service
- The 3-hour daily cap at Renoir / Miyama Coffee cannot be extended
- Café de Crié does not publish its SSID or time limit

Networks that need a sign-up, an email address, or a survey (for example McDonald's) are not supported.

On Tully's and Komeda (USEN), the tool covers only shops where you accept after installing it (see [About USEN](#about-usen)).

## Requirements

macOS 15 or later (uses the built-in `/usr/bin/jq`). Apple silicon and Intel. Tested on macOS 27.

## Before you use it

This is an unofficial tool. It is not endorsed or recommended by Wi2, USEN, or any shop, and the author has not obtained the providers' permission for automatic re-acceptance. The supported networks table shows technical test status.

- Read and accept the terms yourself the first time. After that, the tool re-sends your acceptance automatically without showing the terms page or its notices. Use it only if you understand this and want automatic re-acceptance.
- Use it only within what the provider's terms and the shop's rules allow. If it is unclear whether automated use is allowed, use the normal login page until you have confirmed it with the provider. Do not use it to get around usage limits or required steps.
- There are limits to how it determines acceptance, identifies networks, and detects terms changes. It cannot guarantee a manual first acceptance at every shop.
- Stop using it if you learn of terms changes, see a usage cap or suspension, are asked to stop, or encounter continued failures. To stop and remove it, run `zsh ~/.local/bin/cafe-wifi-okawari-ctl uninstall`.

Before installing, please read the full [Usage notes and automatic acceptance](USAGE-NOTES.en.md).

## Install and use

It runs with your logged-in user's permissions. It talks to Apple's connectivity check page and the Wi‑Fi authentication service, and sends no information to the author's server. It does not handle IDs, passwords, or email addresses. You can inspect the [published scripts](cafe-wifi-okawari.sh) and use the [uninstall command](#uninstall) to remove the background job when you no longer need it.

### 1. Install

Open Terminal (press ⌘+Space and type "Terminal"), paste one of the lines below, and press Enter.

#### Option A: Install the published release (recommended)

It downloads the latest release into a temporary folder and installs it. To update to a new version, run the same line.

```sh
cd "$(mktemp -d)" && curl -fsSLO https://github.com/hiroaki-com/cafe-wifi-okawari/releases/latest/download/cafe-wifi-okawari.tar.gz && tar -xzf cafe-wifi-okawari.tar.gz && zsh cafe-wifi-okawari/install.sh
```

#### Option B: Install with Git

For people who already use Git. It installs the latest `main`, not the published release. To update, run `git pull && zsh install.sh` in that folder.

```sh
git clone https://github.com/hiroaki-com/cafe-wifi-okawari.git && cd cafe-wifi-okawari && zsh install.sh
```

Either way, when you see `Installed:`, you are done. A coffee cup appears in the menu bar, and the tool starts again automatically after you restart your Mac.

### 2. Accept the terms yourself once at the shop

When you join the shop's Wi‑Fi (e.g. `DOUTOR_FREE_Wi-Fi`), macOS opens its login window. Please read the terms and press "accept" as usual.

Once the connection works, the tool records the shop as one where you accepted the terms yourself. When it is recorded, the dot shown when you click the menu bar icon turns green.

- Doutor, Gusto, Starbucks, Renoir, and others (Wi2): even if you accepted before installing, it is recorded right after installation
- Tully's and Komeda (USEN): only shops where you accept after installing are covered (see "About USEN" below)

#### About USEN

At a shop you use for the first time, accept the terms on the login page within 5 minutes of joining the Wi‑Fi, after installing the tool. If you accepted before installing, it applies from the next time you accept on the login page.

For what the tool sends and how it handles terms changes, see [Acceptance and requests on USEN](USAGE-NOTES.en.md#acceptance-and-requests-on-usen).

### 3. Keep using the Wi‑Fi

There is nothing else to do. At each time-out (about 60 minutes at Doutor), the tool accepts the terms again for you.

```text
You accept (first time only)
  → about 60 minutes later, the session times out: you are sent back to the login page and the connection stops
  → the tool notices (within 10 seconds)
  → it re-sends the acceptance; the connection comes back a few seconds later
  → the same happens at every time-out
```

A successful reconnection shows no dialog; the menu bar icon shows ✓ for 10 minutes. What can happen while the connection is down is described in [Caveats](#caveats).

### The menu bar icon

The coffee cup in the menu bar (its steam is drawn as Wi‑Fi waves, with an arrow for "a refill") shows the tool's state. It only reads the tool's files (it writes only a small file that remembers USEN chains, below); it sends nothing over the network.

|  | Meaning |
|---|---|
| <picture><source media="(prefers-color-scheme: dark)" srcset="assets/icon/state-on-white.png"><img src="assets/icon/state-on.png" width="33" height="22" alt="Cup"></picture> | Running |
| <picture><source media="(prefers-color-scheme: dark)" srcset="assets/icon/state-check-white.png"><img src="assets/icon/state-check.png" width="33" height="22" alt="Cup ✓"></picture> | Reconnected automatically within the last 10 minutes |
| <picture><source media="(prefers-color-scheme: dark)" srcset="assets/icon/state-warn-white.png"><img src="assets/icon/state-warn.png" width="33" height="22" alt="Cup !"></picture> | You need to act on this Wi‑Fi |
| <picture><source media="(prefers-color-scheme: dark)" srcset="assets/icon/state-wait-white.png"><img src="assets/icon/state-wait.png" width="33" height="22" alt="Cup …"></picture> | macOS is waiting for you to accept on the login page |
| <picture><source media="(prefers-color-scheme: dark)" srcset="assets/icon/state-off-white.png"><img src="assets/icon/state-off.png" width="33" height="22" alt="Faded cup"></picture> | Stopped. Run `./install.sh` to restart |

Click it to see the current Wi‑Fi's name, whether automatic reconnection is on, the estimated next time-out, and the last three events (the menu is in English only). The dot next to the name is green when automatic reconnection is on, yellow when it is waiting for the next time-out or for you to accept, red when reconnecting failed, and gray when it is not working (not accepted, offline, or stopped). It shows no MAC or IP addresses, so it is safe to show in screen sharing.

- ! appears when you need to accept the terms yourself once, or to check the login page because reconnecting failed. The menu says which
- … appears on any network with a login page, not only supported ones. If the login page does not appear, open `http://captive.apple.com` in a browser
- On USEN Wi‑Fi it shows the chain when it can tell, such as `Tully's (USEN)`, and `USEN` otherwise. It tells them apart by the partly hidden Wi‑Fi name in the macOS system log and does not store that name. It never shows the shop's branch (only Tully's has been checked at a real shop).
- The time-out estimate assumes the shop's limit is 60 minutes and counts from the last authentication on the current network. It is not shown after you rejoined without the login page (waking from sleep, for example). If you uninstall and reinstall the tool, it still counts from the earlier authentication on the same connection. See §3.2 of [DESIGN.md](DESIGN.md) for the exact conditions.

"Hide from Menu Bar" quits the icon; it comes back the next time you log in or run the install steps again. The tool itself keeps running either way. If you do not want the icon at all, reinstall following the install steps, adding ` --no-menubar` before you press Enter (this removes only the icon).

### Check that it is working

Usually the coffee cup in the menu bar is all you need. If the cup is shown and the dot next to the shop's Wi‑Fi name is green, automatic reconnection is on.

<details>
<summary>Check in detail from Terminal</summary>

```sh
zsh ~/.local/bin/cafe-wifi-okawari-ctl status
```

You will see something like this:

```text
Service          loaded (LaunchAgent local.cafe-wifi-okawari)
Schedule         every 10 s, and whenever the network settings change
Program          /Users/you/.local/bin/cafe-wifi-okawari
Version          1.0.0
Last exit code   0 (412 runs since loaded)
Menu bar         running
Current network  gateway 0:0:5e:0:1:1 (doutor), accepted: auto re-authentication on
Accepted         1 network (brand: doutor)
Last auth        2026-05-12 10:05:12 (12 min ago), consent recorded on doutor
Next time-out    around 11:05, in 47 min (if the shop's limit is 60 minutes)
Log              /Users/you/Library/Logs/cafe-wifi-okawari.log (1 line)

Recent log:
  2026-05-12 10:05:12 consent recorded net=… doutor (online)
```

The main fields mean:

| Field | Meaning |
|---|---|
| `Menu bar` | Whether the menu bar icon is running (`running`, `not running`, or `not installed`) |
| `Current network` | Whether the network you are on now is one you accepted. The tool identifies a network by its gateway's MAC address. While the tool is watching a USEN network, it says so |
| `Last auth` | When your own acceptance was recorded, your acceptance on the login page was confirmed, or the tool last re-accepted, on any network |
| `Next time-out` | An estimate from the last authentication on the current network, shown under the same conditions as in the menu bar (on USEN Wi‑Fi you joined for the first time, after the menu bar has told the chain) |

What each log line means is listed in [Troubleshooting](#troubleshooting).

</details>

### Common situations

- You go to another shop: when the login window appears after you join, accept the terms yourself, as in step 2
- A dialog asks you to accept the terms yourself once: the session timed out at a shop the tool has not recorded. It sent nothing, so please accept on the login page yourself. To get the login page, reconnect to the Wi‑Fi or open `http://captive.apple.com` in a browser
- A dialog says it could not reconnect, or that it stopped reconnecting: please check the login page in the same way and accept yourself if needed. The log tells you why ([Troubleshooting](#troubleshooting))
- You want to update: follow the [install](#1-install) steps again. The networks you accepted are kept. To hear about new versions, use Watch → Custom → Releases on GitHub
- You want to stop using it: run `zsh ~/.local/bin/cafe-wifi-okawari-ctl uninstall` ([Uninstall](#uninstall))

### How it works

The overall structure is shown below. launchd, which comes with macOS, starts two parts: the main script and the menu bar display.

```text
launchd [macOS built-in]
Starts and manages the tool
|
+-- cafe-wifi-okawari.sh [added at install]
|   Watches the connection, re-authenticates automatically
|   |
|   +-- Apple [remote]
|   |   Connectivity check, login page detection
|   |
|   +-- Wi2 servers / USEN in-shop devices [remote]
|   |   Where the acceptance is sent
|   |
|   +-- macOS network information and system log [macOS built-in]
|   |   Read only
|   |
|   +-- State files and log [created at run time]
|       Accepted networks, attempt results, etc.
|
+-- menubar.js [added at install]
    Stays running, shows the icon and menu
    |
    +-- menubar.sh [added at install]
        Decides which state to show
        |
        +-- State files and log [created at run time]
        |   Read only
        |
        +-- Network information and system log [macOS built-in]
        |   Read only
        |
        +-- launchd registration of the main script [macOS built-in]
            Read only
```

- It uses the zsh, curl, jq, launchd, and JavaScript for Automation included with macOS. It checks the connection every 10 seconds and re-authenticates when it detects a time-out. You do not need to configure the session length.
- The installer copies the script to `~/.local/bin/cafe-wifi-okawari` and registers it as a user LaunchAgent. It does not use administrator rights (`sudo`).
- Its log and menu never show this Mac's MAC or IP address.
- Networks are identified by the router's MAC address together with the brand (e.g. `doutor`). Shops of the same brand may share the same value, so it cannot always tell shops apart.
- It recognises Wi2 networks from the domain name handed out by the network (`wi2.ne.jp`). On other networks it only checks for a login page at Apple's `captive.apple.com` during the first 5 minutes after joining, as macOS itself does (to find USEN networks). It never sends an acceptance to unrelated networks such as your home Wi‑Fi
- Dialogs follow your macOS language (Japanese or English). Messages from `install.sh` (`cafe-wifi-okawari-ctl`) and the menu bar are in English.

## Caveats

### Each time-out briefly interrupts your connection

At each time-out (at Doutor, about 60 minutes after you accept or the tool re-authenticates), your connection is down until re-authentication completes: up to 10 seconds for the tool to notice, plus a few seconds after it sends the acceptance, so expect at most a dozen or so seconds (measured: about 6 seconds at Gusto and Tully's).

The Wi‑Fi stays connected and your IP address does not change. Many apps carry on once the connection is back, but the effect of the gap varies by app. For example:

- Video calls and online meetings: video or audio may freeze or show "reconnecting". You may be dropped from the call
- Screen sharing and live streaming: what others see stops. A stream may end
- Large uploads and downloads: may fail (apps that cannot resume start over)
- SSH, remote desktop, online games: the session may disconnect

Before an important call, stream, or presentation, please check the next time-out in the menu bar or with `cafe-wifi-okawari-ctl status` and plan around it, or use another connection such as tethering. The tool re-authenticates only after a time-out; it does not renew ahead of time.

### Dialogs appear only when you are offline

A successful reconnection shows no dialog (the menu bar icon shows ✓, and it is logged; see `cafe-wifi-okawari-ctl status`), so the tool does not interrupt your screen every hour. A dialog appears only in these cases, all of them while you have no internet connection:

- You need to accept the terms yourself the first time
- Automatic reconnection failed (once while failures continue)
- The login was refused repeatedly and automatic re-acceptance was stopped
- The USEN terms text changed and automatic re-acceptance was stopped

Dialogs appear in the middle of the screen and close by themselves after 2 minutes. macOS does not show notifications from background jobs, so the usual top-right notifications are not available. Because they are not notifications, Focus modes (such as Do Not Disturb) do not hold them back, and they show up in screen sharing and screen recordings.

### When it cannot reconnect for you

- Rejoining the Wi‑Fi after a time-out (waking from sleep, losing the signal, turning Wi‑Fi off and on): macOS opens its login window and keeps other apps off that Wi‑Fi until you accept, so the tool cannot help. Please accept in the login window yourself. It reconnects automatically again from the next time-out
- On USEN, when macOS opens its login window first: the tool can no longer send anything. Please accept in the login window yourself (see [About USEN](#about-usen))
- While the Mac sleeps: the tool does not run. If the session has timed out when the Mac wakes and the Wi‑Fi is still connected, it re-authenticates within about 10 seconds
- When a daily usage cap is reached (e.g. Renoir): re-authentication is refused and the connection does not come back
- VPN / iCloud Private Relay can prevent the tool from detecting the login page

### Other notes

- Free Wi‑Fi is unencrypted: this tool only reconnects; please protect your traffic with HTTPS or a VPN.
- Terms of use: the tool has no way to lift server-side time or usage limits, and it does not spoof MAC addresses or open multiple sessions. For how it re-sends the acceptance without showing the terms page, please read [Usage notes and automatic acceptance](USAGE-NOTES.en.md).
- Unofficial and not affiliated with any of the companies above. It may break if a portal changes. How it relates to the terms and the law is reviewed in [DESIGN.md](DESIGN.md) §4 (Japanese).

## Uninstall

```sh
zsh ~/.local/bin/cafe-wifi-okawari-ctl uninstall
```

This also removes the menu bar icon, the list of networks you accepted, and the USEN networks being watched. The log at `~/Library/Logs/cafe-wifi-okawari.log` is kept; delete it by hand if you no longer need it.

## Troubleshooting

To check that it is running (what it shows is described in [Check that it is working](#check-that-it-is-working); it sends nothing over the network, and exits with 1 if it is not registered):

```sh
zsh ~/.local/bin/cafe-wifi-okawari-ctl status
```

- If the login window appears, read the terms and notices and accept yourself. If it does not appear, open `http://captive.apple.com` in a browser.
- If automatic reconnection stops or failures continue, check the normal login page for usage caps, suspensions, or terms changes. Run `zsh ~/.local/bin/cafe-wifi-okawari-ctl uninstall` if you need to stop the tool (see [Usage notes](USAGE-NOTES.en.md#when-to-stop-it)).
- For more detail, expand the log reference below.

<details>
<summary>How to read the log and message reference</summary>

The log is written only when something happens:

```sh
tail ~/Library/Logs/cafe-wifi-okawari.log
```

| Log line | Meaning |
|---|---|
| `consent recorded net=… (online)` | The Wi2 network worked although the tool had sent nothing, so it recorded that you accepted on the login page. It re-accepts automatically from the next time-out |
| `consent recorded net=…` | You accepted after the tool had seen the login page; recorded as above |
| `consent pending net=…` | The tool saw the login page on a network it has not recorded, and is waiting for you to accept yourself |
| `captive login seen net=…` | The system log showed that you accepted on the login page. On a network not yet recorded (accepted within 5 minutes of joining), the tool watches it for 24 hours and, if it is a USEN network, sends the acceptance from the first time-out (when the chain is known, it also marks the start of the next time-out estimate). On a network you have accepted before (confirmed within a minute of your acceptance; the brand follows, as in `net=… doutor`), it only marks the start of the next time-out estimate |
| `consent recorded net=… usen (captive login)` | The watched network turned out to be USEN (USPOT-02), so your acceptance at the start was recorded. The tool then sends the acceptance |
| `consent recorded net=… usen` | On a USEN network waiting for your acceptance, the system log showed that you accepted on the login page, so it was recorded |
| `terms changed net=… usen` | The USEN terms text differed from before, so the tool sent nothing and stopped re-accepting automatically. You get a dialog. Read the terms on the login page and accept yourself to resume |
| `re-authenticated api=ok probe=ok net=… t=Ns` | Reconnected automatically (the connection came back N seconds after the tool started sending the acceptance) |
| `network changed net=…` | The Mac switched to another network (e.g. tethering) during a re-authentication or a brand check. That attempt counts as neither a success nor a failure, and nothing is recorded as accepted |
| `login failed xN api=ng probe=ok` | The tool's attempt failed, but the connection came back another way (e.g. the macOS login window) |
| `login failed xN api=… probe=ng` | Could not reconnect. You get a dialog. This also happens when a daily cap (e.g. Renoir) is reached |
| `auto stopped net=… rejected x3` | The auth server refused the acceptance three times in a row, so automatic re-acceptance on this network was stopped (possibly a usage cap, a suspension, or changed conditions). You get a dialog. Check the login page; accepting yourself resumes it |
| `redirect failed xN curl=… http=…` | Could not reach the auth server (timeout or outage). No dialog |
| `redirect failed xN http=… to=…` / `no session_id` | Unexpected response from the auth server (the portal may have changed). You get a dialog on a recorded network |
| `portal unknown xN` | A Wi2 or recorded network showed a login page that is not Wi2's, or a USEN-style redirect led to a page that is not USPOT-02. The tool sends nothing |
| `portal check failed xN` | The tool could not check the USEN page (network error or a response other than 200). It sends nothing |
| `portal mismatch xN mac=… ip=…` | The login page was for a different device (MAC or IP address not this Mac's), so the tool sent nothing |
| `not free wi-fi xN` | A Wi2 network that is not a free "accept the terms" Wi‑Fi. The tool does nothing there |
| `probe failed xN net=… curl=… http=…` | On a Wi2, recorded, or pending network, the connection state could not be checked (non-zero `curl` means a network error; `http` is an unexpected response). The tool sends nothing |

On repeated failures, the retry interval backs off from 30 seconds up to 30 minutes. Every failure is logged (failed status checks only on the 1st, 2nd, 4th, 8th…), and you get a single dialog (plus one more if it stops after repeated refusals). Moving to another shop resets the backoff.

</details>

## Reporting problems and verification results

Choose a bug report or verification report from the [report templates](https://github.com/hiroaki-com/cafe-wifi-okawari/issues/new/choose). Japanese or English is welcome. Include your macOS version, CPU, tool version (unknown is fine), Wi2 / USEN / unknown, steps, and results. Distinguish automatic reconnection after a real time-out from manual acceptance and mock tests.

Issues are public. Do not attach full logs, `cafe-wifi-okawari-ctl status` output, screenshots, or network captures. Status output and logs include network details and times; the menu also shows times. Exclude MAC/IP addresses (including the gateway), SSIDs, shop names/locations, visit dates or activity times, usernames/personal file paths, authentication URLs, cookies, and tokens from the title and body as well.

For errors, manually enter only a category from the log reference above (e.g. `probe failed`) and numeric `curl` / `http` codes. Whole log lines and response bodies are not needed. You can keep your local records unchanged. Check the preview for private information before posting.

## Development

```sh
zsh test/run.sh   # branch tests with mocked curl, launchctl, etc. (no real network access)
```

Design notes, security model, and verification status: [DESIGN.md](DESIGN.md) (Japanese).

## License

[MIT](LICENSE)
