# 📊 Grid Trading EA for MetaTrader 5

A production-ready **Grid Trading Expert Advisor** for MT5 with event-driven architecture and smart grid management.

![MQL5](https://img.shields.io/badge/MQL5-Expert%20Advisor-blue)
![MT5](https://img.shields.io/badge/Platform-MetaTrader%205-brightgreen)
![Version](https://img.shields.io/badge/Version-4.10-orange)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## ⚡ How It Works

The EA deploys a **fixed-distance grid** of price levels around a manually set **Anchor Price (Level 0)**. When price drops to a grid level, a **Buy** position opens with **Take Profit** set at the next level above. Each level operates independently.

```
Level +3  ─────────────  ← TP for Level +2
Level +2  ─────────────  ← TP for Level +1
Level +1  ─────────────  ← TP for Level 0
Level  0  ═════════════  ← ANCHOR (Buy triggers here)
Level -1  ─────────────  ← Buy triggers here
Level -2  ─────────────  ← Buy triggers here
```

### Grid Logic

1. Price drops to **Level N** → **Buy** opens
2. **TP** is set at **Level N+1** (next level above)
3. Level **locks** while trade is active
4. TP hit → position closes → level **unlocks** for re-entry
5. Max positions reached → EA **pauses** until one closes

---

## 🔧 Input Parameters

| Parameter | Description | Example (Gold) |
|-----------|-------------|----------------|
| **Lot Size** | Trade volume (min 0.01) | `0.01` |
| **Level 0 Price** | Anchor price (0 = auto-detect) | `2350.00` |
| **Grid Distance (Price)** | Gap between levels in price | `5.0` ($5) |
| **Grid Distance (Points)** | Gap in points (if price = 0) | `500` |
| **TP Distance (Price)** | Take profit distance | `5.0` |
| **Max Open Positions** | Pause when limit reached | `5` |
| **Slippage** | Order execution tolerance | `30` |

> **Tip:** Set both distance fields to `0` for smart auto-detection (~0.2% of price).

---

## 📈 Chart Visualization

- 🟡 **Gold line** — Anchor Level (L0)
- 🟢 **Green line** — Active trade level
- ⚪ **Gray dotted** — Inactive level
- **Status panel** — Shows open positions, active levels, and EA state

---

## 🚀 Installation

1. Copy `GridTradingEA.mq5` to your MT5 **Experts** folder:
   ```
   [MT5 Directory]\MQL5\Experts\
   ```
2. Open **MetaEditor** → compile the file (**F7**)
3. In MT5, drag the EA onto any chart
4. Set your **Level 0 Price** and **Grid Distance**
5. Enable **AutoTrading** ✅

---

## 🧪 Backtesting

1. Open **Strategy Tester** (`Ctrl+R`)
2. Select `GridTradingEA`
3. Set the testing period and symbol
4. Configure inputs (Level 0 should be within the test price range)
5. Enable **Visual Mode** to see grid lines
6. Click **Start**

---

## 🛡️ Features

- **Event-driven** — No heavy OnTick loops scanning history
- **State recovery** — Restores positions after EA restart
- **Auto-detection** — Anchor price and grid distance auto-set if left at 0
- **Broker-compatible** — Auto-detects filling mode (FOK/IOC/RETURN)
- **All instruments** — Works on Forex, Gold, Indices, etc.
- **Clean visualization** — Only shows nearby grid levels to keep chart clean

---

## ⚠️ Risk Disclaimer

Grid trading carries significant risk. This EA does **not** use stop losses by design. Use proper risk management and test thoroughly before live trading.

---

## 📝 License

MIT License — free to use and modify.
