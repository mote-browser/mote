# Security

Mote holds passwords, passkeys and browsing history, so a security problem in
it is worse than an ordinary bug. Please report one privately.

## Reporting

Use GitHub's private reporting: the repository's **Security** tab ›
[**Report a vulnerability**](https://github.com/mote-browser/mote/security/advisories/new).
Only maintainers can read it. Tell us what you found, where it is in the
code, and the steps to reproduce it. A proof of concept is welcome as long as
it runs against your own machine and accounts, never anyone else's.

Keep it out of public issues and pull requests until a release fixes it. A
pull request with just the fix, not the attack, is fine.

## After you report

- A person replies, not a bot.
- The fix ships in the next release, and Mote's own updater brings it to
  people within a day of that.
- The changelog thanks you by name once it's out, if you'd like it to.

## In scope

Anything that lets a page, an extension, another app or someone on the
network go past what they're allowed: reading files, passwords, passkeys,
cookies or history; getting around a permission; opening another app
without asking; or changing Mote itself. That includes the updater, Mote's
keychain items, the extension layer and the bench socket (`Tools/bench`).

A site that misbehaves, or an extension that acts unlike it does in Chrome,
is an ordinary bug: open an [issue](https://github.com/mote-browser/mote/issues).
