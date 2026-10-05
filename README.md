# TradeSync

**Where discipline compounds.**

TradeSync is a native macOS trading journal. It logs your trades from your broker or prop firm, then gives you a place to add what only you know: the chart, your confluences, and why you took the trade.

## Features

- **Dashboard**: net P&L, profit factor, trade and day win rates, a P&L calendar, a cumulative equity curve, and an Edge Score.
- **Daily Journal**: a folder for each trading day. Each trade records symbol, direction, size, entry, exit, stop loss, take profit and P&L, and you can attach TradingView screenshots, confluence tags and notes.
- **Trade Review**: review any week, month, three months or year. It shows what worked, what your tagged mistakes cost, a process check, and your best and worst trades.
- **Calendar and Reports**: performance by day, time, symbol, setup and duration.
- **Multiple accounts**: keep live, funded and evaluation accounts separate, and switch between them from the sidebar.
- **Win streak tracker**: green days in a row, plus your best run.

## Install

1. Download **TradeSync-Share.zip** from the [Releases](../../releases) page.
2. Unzip it and drag **TradeSync.app** into Applications.
3. Follow **How to Install TradeSync.txt** in the zip. The first launch has to be approved once in System Settings → Privacy & Security, because the app isn't distributed through the App Store.

TradeSync needs macOS 14 (Sonoma) or later and runs on both Apple Silicon and Intel Macs. On first launch it asks for your name and opens with sample data you can remove from the Dashboard.

## Connecting accounts

**Prop firm accounts on Tradovate (Tradeify, Apex and others).** Tradovate doesn't let third-party apps read prop firm or evaluation accounts, so TradeSync imports Tradovate's own report. Export the **Orders** report from Tradovate's Account Reports; the CSV lands in your Downloads folder and TradeSync logs the trades within a minute. It rebuilds entry, exit, stop loss, take profit, size and P&L from the orders, and correctly handles scaling in, partial exits and reversals.

**MetaTrader 5 (FTMO, FundedNext, MT5 brokers).** Syncs automatically through [MetaApi](https://metaapi.cloud), a third-party service with a free tier. Add your MT5 login there, then paste the API token and account ID into TradeSync.

## Privacy

Everything stays on your Mac, in `~/Library/Application Support/TradeSync/`. Nothing is uploaded or shared, and the app has no account or analytics.

## Building from source

Requires macOS 14 or later and a Swift toolchain (Xcode or the Command Line Tools).

```bash
./Scripts/build_app.sh
```

This compiles a universal (Apple Silicon + Intel) app, installs it to `~/Applications`, and packages `build/TradeSync-Share.zip` for sharing.

With Command Line Tools 27 or later, the script builds against the macOS 26 SDK when it's installed. That's because the macOS 27 SDK's SwiftUI relies on a compiler plugin that only full Xcode includes.

### Development aids

- `TRADESYNC_DATA_DIR=/some/empty/folder` points the app at a separate data folder, which lets you test a first launch without touching your own journal.
- `TradeSync --snapshot <folder>` renders every page to PNG without opening a window.
- `TradeSync --parse-tradovate <file.csv>` prints the trades rebuilt from a Tradovate export.
