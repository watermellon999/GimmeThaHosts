# GimmeThaHosts

A small bash script that helps you build a custom `/etc/hosts` file to block unwanted domains for privacy, security, or focus.

In simple terms:  
👉 it collects domain lists from multiple sources,  
👉 applies your allow/block rules,  
👉 and generates a ready-to-use hosts file — safely and reproducibly.

You stay in control of **what gets blocked and what doesn’t**.

> ## 🚚 This project has moved
>
> The local-build version of this project is now maintained in two places,
> depending on how you want to run it:
>
> - **CI-first version (recommended):** [`watermellon999/BuildTheHosts`](https://github.com/watermellon999/BuildTheHosts)
>   — builds hosts files on GitHub Actions and
>   publishes them to a rolling `latest` release. No local installation,
>   supports multiple profiles,
>   no `/etc/hosts` edits on your machine, no cache to manage.
>   **If you know how to fork a repo and enable a workflow, use this one.**
> - **Local-build version (this repo):** still the right choice if you
>   want to run the build on your own machine and benefit from the
>   archive cache and `--offline` mode. See *Running it yourself* below.
>
> The two repos are not meant to be mixed. Pick the one that matches
> how you want to run it.

---

## Requirements

-   bash and coreutils
-   curl

> **Announce:** There is a 'aria2c' branch you can switch to, for better reliability in downloding larger source files. Your host machine should have a aria2c binary and its location should have been added to PATH environment variable. 

---

## How it works (very briefly, non-technical)

-   Downloads domain lists from the sources you choose
    
-   Keeps local archived copies so things still work offline
    
-   Applies your personal allowlist and blocklist
    
-   Produces a clean `hosts` file
    
-   Asks before touching your system file
    

No magic, no background services, no telemetry.


---

## Running it yourself (optional)

The script is a single bash file and has no install step. You need `bash`, `coreutils`, and `curl` (and `aria2c` on the aria2c branch). Clone the repo, review the four config files, and run:

```
git clone https://github.com/watermellon999/GimmeThaHosts.git
cd GimmeThaHosts
```

edit these to match your setup — do not skip this
```
$EDITOR sources.txt
$EDITOR whitelist.txt
$EDITOR blacklist.txt
$EDITOR headers.txt

chmod +x update.sh
./update.sh
```

The script:

- downloads every source in `sources.txt` into `./archive/`,
- skips re-downloading unchanged files using ETag or `Content-Length`,
- applies `blacklist.txt` first, then filters out anything matched by
  `whitelist.txt` (exact domains and `regex:` patterns),
- writes `hosts.blocked` in the current directory,
- asks before copying it to `/etc/hosts`.

Nothing is written outside the repo until you answer `y` at the prompt.

### Offline mode

If you've run the script at least once, `./archive/` holds a copy of every source. To rebuild from those copies without touching the network
— useful when offline, on a metered connection, or when a source is down:

```
./build.sh --offline
```

In offline mode the script never makes an HTTP request. Sources that have an archive are used; sources that don't are skipped with a warning. A full build from warm archives takes a second or two.

### Restoring `/etc/hosts`

Keep a backup before the first run:

```
sudo cp /etc/hosts /etc/hosts.bak
```

The script does not create one for you. To undo a build:

```
sudo cp /etc/hosts.bak /etc/hosts
```

---

## Configuration files (important)

This project is intentionally **opinionated for my personal needs**.  
You **must review and change these files** to match *your* setup.

### `sources.txt`

A list of blocklist sources (URLs or local files).

⚠️ **Important warning**  
My source list includes **very aggressive / extreme blocklists**.  
They **will break major services**, including (but not limited to):

-   Social media platforms
    
-   Messaging apps
    
-   CDNs used by popular websites
    
-   Some app update servers
    

This is **by design for my use case**, not a recommendation.  
If you don’t want things to break — **replace these sources**.

---

### `whitelist.txt`

Domains you explicitly **allow**.

-   Either exact matches or regex patterns prefixed by 'regex:' are whitelisted.
eg: 
    video.example.com
    regex:^video-[A-Za-z0-9]{4}-[0-9]\.xx.example\.com$
    
-   Subdomains are **not** automatically allowed
    
-   Useful when a blocklist is too aggressive
    

This file reflects *my* tolerances — yours will differ.

---

### `blacklist.txt`

Domains you explicitly **block**, regardless of sources.

-   Highest priority
    
-   Always applied first
    
-   Useful for adding personal rules
    

Again: customize freely.

---

### `headers.txt`

The static header portion of the hosts file.

-   Localhost entries
    
-   IPv4 / IPv6 defaults
    
-   OS-specific lines if needed
    

Replace or edit this if your system requires something different.

---

## Source links

Below are the blocklist sources used in this setup.  

- [OISD](https://oisd.nl/)
- [Hagezi/dns-blocklists](https://github.com/hagezi/dns-blocklists)
- [StevenBlack/hosts](https://github.com/StevenBlack/hosts/releases)
- [The Block List Project](https://blocklistproject.github.io/Lists/)
- [FMHY Filterlist](https://github.com/fmhy/FMHYFilterlist)

---

## License

This project is licensed under the **GNU Affero General Public License v3 (AGPLv3)**.

You are free to use, modify, and share it —  
but improvements and network-used modifications must remain open.

---

## Special thanks ❤️

-   All **blocklist maintainers and contributors**
    
-   The **privacy, security, and FLOSS communities**
    
-   Everyone sharing knowledge, tools, and data openly
    

This project stands on the shoulders of a lot of unpaid, often invisible work.

---
