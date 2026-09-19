# GimmeThaHosts

A small script that helps you build a custom `/etc/hosts` file to block unwanted domains for privacy, security, or focus.

In simple terms:  
👉 it collects domain lists from multiple sources,  
👉 applies your allow/block rules,  
👉 and generates a ready-to-use hosts file — safely and reproducibly.

You stay in control of **what gets blocked and what doesn’t**.

---

## How it works (very briefly, non-technical)

-   Downloads domain lists from the sources you choose
    
-   Keeps local archived copies so things still work offline
    
-   Applies your personal allowlist and blocklist
    
-   Produces a clean `hosts` file
    
-   Asks before touching your system file
    

No magic, no background services, no telemetry.

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
