# Usage notes and automatic acceptance

[Back to README](README.en.md) · [日本語](USAGE-NOTES.md) | English

This is an unofficial tool that automates reconnecting to free Wi‑Fi that you yourself are allowed to use. It is not endorsed or recommended by Wi2, USEN, or any shop, and the author has not obtained Wi2's or USEN's permission for automatic re-acceptance. The [supported networks table in the README](README.en.md#supported-networks) shows technical test results and expectations; it does not mean automated use is permitted.

## When you may use it

- Check the current terms of the Wi‑Fi you use (for Wi2, the [Free Wi‑Fi Service Terms](https://wi2.co.jp/rules/free-wifi.html), in Japanese; for USEN, the terms shown on the login page), its connection conditions, and the shop's rules, and use the tool only within what you are allowed to do.
- Being allowed to reconnect as often as you like is not the same as being allowed to automate it. If it is unclear whether automated use, or connecting without going through the login page, is allowed, please use the normal login page until you have confirmed it with the provider.
- Do not use it to get around required steps such as time or usage limits, suspensions, identity checks, sign-ups, or surveys. The tool does not count usage time or reconnections. Please check the notices in the shop too (for example, Doutor's [flyer](https://www.doutor.co.jp/dcs/service/images/doutor_free_wi-fi.pdf) says "60min three times per day" in English, while the Japanese text only says you can re-authenticate after 60 minutes).
- Stop using it if the shop or the provider asks you to. Even when Wi‑Fi can be reconnected, the shop's own rules, such as how long you may stay, still apply.

## About automatic acceptance

Please accept the terms yourself on the login page the first time. macOS keeps a Wi‑Fi with a login page unusable until you accept, and the tool never sends an acceptance on a network it has not recorded. So when a Wi2 network works (or the connection comes back after the tool saw the login page), the tool infers that you accepted and records that network. On USEN, it records the network only after confirming in the system log that you accepted on the login page (see [About USEN](README.en.md#about-usen)). At later time-outs it does not show the terms page; it sends the acceptance directly to the authentication API (the same request as the login page's "accept" button). Notices shown on the login page are not displayed either. Please use the tool only if you understand this and want automatic re-acceptance.

The tool does not verify your act of accepting, and it does not detect changes to the terms. Because it skips the terms page, it cannot see a notice of changes shown there. On USEN, all it checks is that an acceptance happened on a login page (the system log does not say on which network) and that the terms text on the page has not changed. Network identification is also limited, so it cannot guarantee a manual first acceptance at every shop (at another shop of the same brand, it may send the acceptance without one). If you learn that the terms have changed or new conditions apply, stop the tool and do not resume automatic reconnection until you have reviewed them.

## When to stop it

The tool cannot tell a refusal due to a usage cap or suspension from a temporary network problem. If the auth server refuses the acceptance (on USEN, if the device responds) three times in a row on the same network and the connection does not come back, the tool stops re-accepting on that network and tells you in a dialog (accept on the login page yourself to resume). On timeouts and server errors it does not stop; it keeps retrying with a growing interval (up to 30 minutes). If a cap or suspension is shown, or failures continue, stop automatic reconnection and check the normal login page.

Run `./install.sh uninstall` in the repository directory to remove the background job and the list of recorded networks.

The license of this tool does not grant any right to use a Wi‑Fi service, nor permission for any action that violates the provider's terms.
