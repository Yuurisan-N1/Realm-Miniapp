<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=MinerX%20Realm%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Mining%20Cycle%20%7C%20Task%20Automation%20%7C%20Proxy%20Support&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Mining+Start+%2B+Claim+Automation;Task+Claim+%7C+Daily+Rewards+%7C+Check+In;Multi-Account+%7C+Sequential+Processing;Proxy+Support+%7C+One+Proxy+Per+Account"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14%2B-4B275F?logo=elixir&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-MinerX%20Realm-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>MinerX Realm Bot</b> is a full automation bot for the MinerX Realm Telegram Miniapp.<br/>
  It handles the complete daily cycle: mining session start and claim, task rewards, daily streak, spin, chest and gift pick, check in rewards, leaderboard position and the referral bonus, all running automatically across multiple accounts with proxy support and a live countdown between cycles.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+` with Erlang/OTP `25+`
- Git

---

## Installation

### Install Elixir

Elixir runs on the Erlang virtual machine, so **Erlang/OTP is required** Elixir cannot run without
it. Every package manager below installs Erlang/OTP for you as a dependency. The only path that needs
a separate Erlang step is the Windows manual installer (see below).

**Windows:**

*Option A package manager (recommended, installs Erlang automatically):*

```cmd
winget install Elixir.Elixir
```

*Option B manual installer (two installers, in this order):*

1. Download and run the **Erlang/OTP installer** from https://www.erlang.org/downloads
2. Run `erl -s halt` to check which OTP version you got
3. Download the **Elixir installer built for that exact OTP** from https://elixir-lang.org/install.html (`elixir-otp-<N>.exe`) and run it

Then open Command Prompt and verify:

```cmd
elixir --version
```

The output prints both versions, for example `Elixir 1.14.0 (compiled with Erlang/OTP 25)`.

**Linux (Ubuntu / Debian):**

```bash
sudo apt-get update
sudo apt-get install -y elixir
elixir --version
```

**macOS:**

```bash
brew install elixir
elixir --version
```

> If you do not have Homebrew, install it first from https://brew.sh

**Termux (Android):**

```bash
pkg update && pkg upgrade -y
pkg install elixir -y
elixir --version
```

> If the `elixir` package is not available in your Termux repository, install an Ubuntu environment first with `pkg install proot-distro`, then `proot-distro install ubuntu`, then `proot-distro login ubuntu` and run the Linux command above inside it.

---

### Clone and Install

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/Realm-Miniapp.git
cd Realm-Miniapp
```

**Install dependencies:**

This bot uses only the Elixir standard library, so there is nothing to install. Erlang/OTP was already installed by the step above.

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with Telegram WebApp `initData` for each account, one per line:

```
user=%7B%22id%22...&hash=abc123
user=%7B%22id%22...&hash=def456
```

> `initData` can be obtained from the browser DevTools when opening the MinerX Realm Miniapp on Telegram Web. The user id is read from the `user` query parameter, so no separate id column is needed.

### 2. Proxy (proxy.txt)

Fill `proxy.txt` with proxies, one per line (optional, leave empty to run without proxy):

```
host:port
host:port:user:pass
http://user:pass@host:port
```

Proxies are assigned to accounts by index in round-robin order.

### 3. Bot Settings (config.json)

`sleep_seconds` controls how many seconds the bot waits between cycles. If `config.json` is missing, it is created automatically with a default of `3600` seconds.

```json
{
  "settings": {
    "sleep_seconds": 3600,
    "requires_membership": true
  }
}
```

---

## Running the Bot

**Linux / macOS:**

```bash
elixir --erl "+Bd" bot.exs
```

**Windows:**

```cmd
elixir --erl "+Bc" bot.exs
```

Or just double click `run_pc.bat`, which runs the Windows command above.

---

## Features

### Account State
At the start of every account the bot reads the full account snapshot and logs the account name together with the current coin balance. A banned account is reported and skipped before any other request is sent.

### Mining Session
When no mining session is running the bot opens one. When a session is still running the bot re-reads the snapshot and prints how much time is left, then moves straight on to the daily rewards it never parks the cycle on a multi-hour countdown, so every account is processed on every pass. Once the timer has run out, the next cycle claims the reward. The claimed amount is not taken from the request: the bot re-reads the account afterwards and logs the real balance gain, so a claim that credited nothing is never reported as a reward.

### Daily Rewards
The daily streak, the lucky spin, the chest and the gift pick are claimed in order. The amount logged is the one the server returns with the claim. When every one of them was already collected for the day the bot says so once instead of repeating four identical lines.

### Task Rewards
Every task from the task list is claimed in order, except the ones the `requires_membership` switch in `config.json` removes: tasks whose `requires_membership` field is `false` are only claimed while that key is `true`. The reward logged is the amount the server returns with the claim itself. A task that still requires a manual channel join is reported as such and skipped, and a task that was already completed is reported instead of being claimed twice. When the list is empty the bot says so once.

### Check In
The five check in tasks are attempted in order. The reward that the server credits is logged with the task number. When every attempt is refused because the membership was not verified, that reason is reported once.

### Leaderboard
The account is looked up by its own username in the published leaderboard and its position is printed together with the number of ranked miners. An account that is not ranked yet is reported as such.

### Referral Bonus
The referral commission is collected when the server reports one above the minimum. Accounts with nothing pending are reported as such.

### Multi Account
All accounts in `data.txt` are processed sequentially within every cycle. Each account block starts with its own proxy line, and blocks are separated by one blank line so the mapping between an account and its egress is auditable in the log.

### Proxy Support
Proxies are loaded from `proxy.txt` and assigned to accounts by position in round-robin order. Proxy credentials are masked in log output. Running without proxies is fully supported.

### Auto Countdown
Every wait inside the cycle displays a live `HH:MM:SS` countdown in place, and after all accounts complete a cycle the bot shows a countdown until the next cycle starts. A mining session that is still counting down is reported as a single line instead, so it never stalls the rest of the cycle.

---

## File Structure

```text
Realm-Miniapp/
├── bot.exs         # Main bot, full daily cycle automation
├── config.json     # Sleep duration between cycles
├── data.txt        # Account initData, one per line
├── proxy.txt       # Proxy list, one per line (optional)
├── run_pc.bat      # Launcher for Windows
├── LICENSE         # License file
└── utils/
    ├── banner.ex   # Banner display on startup
    └── json.ex     # JSON encoder and decoder
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>