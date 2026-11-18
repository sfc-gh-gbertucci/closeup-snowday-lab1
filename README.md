# Close-Up SnowDay — Lab 1: From Zero to AI Agent

A beginner hands-on lab in two parts for the Close-Up International SnowDay. It uses **synthetic pharma market data** (pharmacies, laboratories, products, doctors, prescriptions, sell-out and field notes). None of it is real Close-Up or customer data.

| Part | When | Duration | Guide (read on GitHub) | Interactive version |
|---|---|---|---|---|
| **1A — Data Foundation** | 25/11 | ~50 min | [lab1a_data_foundation.md](lab1a_data_foundation.md) | [HTML](lab1a_data_foundation.html) |
| **1B — From Data to AI Agent** | 26/11 | ~75 min | [lab1b_ai_agent.md](lab1b_ai_agent.md) | [HTML](lab1b_ai_agent.html) |

- **1A:** Snowsight, internal stages and `COPY INTO` (CSV/JSON), Time Travel, views, Dynamic Tables and a Snowsight dashboard.
- **1B:** Cortex AI Functions, Semantic Views, Cortex Search, a Cortex Agent in Snowflake Intelligence, least-privilege roles, resource monitors and cost monitoring.

Lab 1B continues from the objects created in Lab 1A. If you missed Day 1, step 1 of Lab 1B explains how to catch up.

## How to use

1. `git clone https://github.com/sfc-gh-gbertucci/closeup-snowday-lab1.git`, or use **Code → Download ZIP** and unzip it.
2. Read the guide (`.md`) directly on GitHub, or for **Copy** buttons and progress tracking open the `.html` file in your browser after downloading. Run each SQL block in a Snowsight SQL worksheet.
3. Prefer plain SQL files? `sql/lab1a/` and `sql/lab1b/` hold every SQL block, one file per step (`stepNN.sql`).

> Blocks marked `-- fails` are meant to fail (for example, permission tests). Steps done in the Snowsight UI (dashboard, Snowflake Intelligence) are described only in the HTML guides.

**Requirements:** a Snowflake account with `ACCOUNTADMIN`.
**Cleanup:** step 8 of Lab 1B.
