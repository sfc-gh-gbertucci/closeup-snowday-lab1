-- Step 6: Use the Agent in Snowflake Intelligence
-- Source: lab1b_ai_agent.html

-- Account-level view of Snowflake Intelligence / agent consumption (may lag up to a few hours)
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY
ORDER BY START_TIME DESC
LIMIT 20;

-- Confirm the agent and both tools it depends on exist and are reachable
SHOW AGENTS IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
SHOW CORTEX SEARCH SERVICES IN SCHEMA CLOSEUP_HOL1.AI;
SHOW SEMANTIC VIEWS IN SCHEMA CLOSEUP_HOL1.ANALYTICS;
