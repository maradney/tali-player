# Security Policy

## Reporting a vulnerability

Please report security issues **privately** rather than opening a public
issue. Use GitHub's [private vulnerability
reporting](https://github.com/maradney/tali-player/security/advisories/new),
which goes only to the maintainer.

This is a hobby project maintained by one person, so please be realistic
about response times. I will acknowledge a report when I see it and tell you
honestly whether and when I can fix it.

## Supported versions

Only the latest release gets fixes. There is no long-term support branch.

## What is in scope

Tali is a local desktop and mobile application with no backend, so the
interesting surface is narrow:

- Mishandling of the credentials you enter (they are held in OS-level secure
  storage — DPAPI on Windows, the Android Keystore on Android)
- Credentials or playlist URLs leaking into logs, crash output, the
  Diagnostics screen, or the settings backup file
- Anything that causes the app to contact a host you did not configure
- Parsing bugs reachable from a malicious playlist, EPG feed, or panel
  response — the app parses M3U, XMLTV and JSON from servers it does not
  control
- Parental-control or kids-profile restrictions being bypassed

## What is out of scope

- The security of your IPTV provider or its panel software
- Anything requiring an attacker to already have access to your unlocked
  machine or user account
- The absence of code signing on the Windows build. This is known and stated
  in the README: the project does not currently pay for a certificate
- Reports from automated scanners with no demonstrated impact
