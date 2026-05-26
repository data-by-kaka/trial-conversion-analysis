- TASK 2 — SQL-BASED DATA WAREHOUSE MODEL
-- Splendor Analytics Trial Activation Challenge
-- ============================================================
-- I built this model to answer one question:
-- which organisations actually got value from their trial?
--
-- Rather than dumping everything into one messy query, I structured it in layers so each step has one job:

--   raw_events           → the data exactly as it came in
--   stg_events           → cleaned up and ready to work with
--   fct_trial_goals      → did each org hit each goal?
--   fct_trial_activation → did they hit all three?
-- ============================================================


-- SECTION 1: DATABASE SETUP
-- First things first, I created a dedicated database for
-- this project so everything lives in one clean place
-- and doesn't mix with anything else.
-- ============================================================

CREATE DATABASE trial_analysisdb;

USE trial_analysisdb;

-- SECTION 2: RAW LAYER: raw_events
-- This is where the data lands when it first comes in.
-- I deliberately left everything here untouched, no cleaning, no reformatting, nothing. The reason I stored
-- the date columns as VARCHAR is that SQL Server kept throwing conversion errors during the CSV import because
-- of the date format. Keeping them as plain text at this stage made the import go through cleanly. I'll convert
-- them to proper dates in the staging layer.The event_id is just an auto-numbered ID so every row has something unique to identify it by.
-- ============================================================

DROP TABLE IF EXISTS raw_events;
GO
-- DA_task.csv loaded here via SSMS Import Flat File wizard

-- Just confirming the full dataset came through intact

SELECT COUNT(*) AS total_rows FROM raw_events;     -- gives 170,526
SELECT TOP 5 * FROM raw_events;

-- SECTION 3: STAGING LAYER — stg_events

-- The raw table is a bit rough, so I cleaned it up here
-- before doing any real analysis. Three things needed fixing:
--
-- First, all the date columns were stored as text strings.
-- I converted them to proper DATETIME2 values so I could
-- actually compare dates. TRY_CONVERT is the safe version
-- of this — if a value can't be converted it just returns
-- NULL rather than crashing the whole query.
--
-- Second, the dataset had roughly 67,000 exact duplicate
-- rows — probably an artifact of how the events were
-- exported. I used ROW_NUMBER() to number each group of
-- identical rows and then kept only the first one.
--
-- Third, some events in the data happened outside the
-- 30-day trial window — either before it started or after
-- it ended. Those don't tell us anything useful about trial
-- behaviour so I filtered them out too.
--
-- What's left after all three steps is a clean, trustworthy
-- event log that the two mart tables are built on top of.
-- ============================================================

DROP VIEW IF EXISTS stg_events;


CREATE VIEW stg_events AS

WITH

-- I started by converting all the date strings into real
-- DATETIME2 values. Without this step I couldn't do any
-- date comparisons later. TRY_CONVERT returns NULL
-- if a value is malformed, which is much better than
-- the query falling over unexpectedly.

dated AS (
    SELECT
        organization_id,
        activity_name,
        TRY_CONVERT(DATETIME2, timestamp)    AS event_ts,
        TRY_CONVERT(DATETIME2, trial_start)  AS trial_start,
        TRY_CONVERT(DATETIME2, trial_end)    AS trial_end,
        TRY_CONVERT(BIT, converted)          AS converted,
        TRY_CONVERT(DATETIME2, converted_at) AS converted_at
    FROM raw_events
),

-- Next I tackled the duplicates. ROW_NUMBER() assigns a
-- number to each row within a group of identical events
-- the first one gets 1, the second gets 2 and so on.
-- By keeping only rn = 1 in the next step, I end up with
-- exactly one copy of each event.

deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY organization_id,
                         activity_name,
                         event_ts,
                         trial_start,
                         trial_end
            ORDER BY event_ts
        ) AS rn
    FROM dated
),

-- Finally I filtered down to only events that actually
-- happened during the trial. If an organsiation did something before
-- their trial started or after it ended, I excluded it,
-- that activity doesn't reflect their trial experience.
-- Rows where the date conversion failed (NULL) also get
-- dropped here since they can't be validated.

in_window AS (
    SELECT *
    FROM deduped
    WHERE rn = 1                    -- one copy per event, duplicates removed
      AND event_ts  >= trial_start  -- happened on or after trial day one
      AND event_ts  <= trial_end    -- happened on or before the last day
      AND event_ts   IS NOT NULL    -- conversion worked
      AND trial_start IS NOT NULL
      AND trial_end   IS NOT NULL
)

-- This is the clean event log everything else is built on.
-- days_into_trial tells us how far into their trial each
-- action happened — useful context for understanding
-- when during the trial orgs got active.

SELECT
    organization_id,
    activity_name,
    event_ts,
    trial_start,
    trial_end,
    converted,
    converted_at,
    DATEDIFF(DAY, trial_start, event_ts) AS days_into_trial
FROM in_window;


-- Confirming the clean numbers match what I saw in the analysis

SELECT COUNT(*) AS clean_rows FROM stg_events;  -- 102,895

SELECT COUNT(DISTINCT organization_id) AS unique_orgs FROM stg_events; -- 966

-- SECTION 4: MARTS LAYER: fct_trial_goals

-- This is the first of the two tables the brief asked for.
--
-- The three goals came directly out of the Task 1 analysis.
-- I looked at which activities had above baseline conversion
-- rates and which ones showed the biggest gap between orgs
-- that converted and those that didn't. These three came
-- out on top every time I cut the data:
--
-- Goal 1: Core Scheduling Activated
--   The org created at least 3 shifts. One or two shifts
--   could just be someone exploring. Three or more tells
--   me they actually sat down and started building a real
--   working schedule. (Scheduling.Shift.Created >= 3)
--
-- Goal 2: Scheduling Depth Reached
--   The org applied at least one shift template. Templates
--   are a time-saving feature, using one means the org
--   has moved past just testing things and is now thinking
--   about working smarter. (Scheduling.Template.ApplyModal.Applied >= 1)
--
-- Goal 3: Time & Attendance Activated
--   At least one team member clocked in using PunchClock.
--   This is the moment the product stops being just a
--   scheduling tool and becomes part of the daily routine.
--   (PunchClock.PunchedIn >= 1)
--
-- The result is one clean row per organisation with a pass
-- or fail flag for each goal and the underlying counts
-- so anyone can audit exactly how the flags were set.

DROP VIEW IF EXISTS fct_trial_goals;


CREATE VIEW fct_trial_goals AS

WITH

-- I needed to count how many times each org performed each
-- of the three goal activities during their trial.
-- SUM(CASE WHEN ...), it scores 1 for every matching row and 0 for
-- everything else, then adds them up per org.
-- GROUP BY organisation_id collapses the whole event log
-- down to one summary row per org.

activity_counts AS (
    SELECT
        organization_id,

        -- how many shifts did this org create in total?
        SUM(CASE WHEN activity_name = 'Scheduling.Shift.Created'
                 THEN 1 ELSE 0 END)  AS shifts_created,

        -- how many times did they actually use a template?
        SUM(CASE WHEN activity_name = 'Scheduling.Template.ApplyModal.Applied'
                 THEN 1 ELSE 0 END)  AS templates_applied,

        -- how many times did someone on their team clock in?
        SUM(CASE WHEN activity_name = 'PunchClock.PunchedIn'
                 THEN 1 ELSE 0 END)  AS punch_ins,

        -- grab the org-level info — same value on every row
        -- for a given org so MAX/MIN just picks one reliably
        MAX(CAST(converted AS INT))  AS converted,
        MAX(converted_at)            AS converted_at,
        MIN(trial_start)             AS trial_start,
        MAX(trial_end)               AS trial_end

    FROM stg_events
    GROUP BY organization_id
)

-- Now I turn the counts into simple pass/fail flags using
-- the thresholds I defined in Task 1. A 1 means the org
-- cleared that bar, a 0 means they didn't. I kept the raw
-- counts in the output too so it's easy to see an org that
-- scored 2 shifts vs one that scored 25, both fail Goal 1
-- but the story behind each is very different.

SELECT
    organization_id,
    trial_start,
    trial_end,
    converted,
    converted_at,

    -- did they create enough shifts to show real scheduling intent?
    CASE WHEN shifts_created    >= 3 THEN 1 ELSE 0 END  AS goal1_met,

    -- did they go deep enough to use templates?
    CASE WHEN templates_applied >= 1 THEN 1 ELSE 0 END  AS goal2_met,

    -- did anyone on their team actually clock in?
    CASE WHEN punch_ins         >= 1 THEN 1 ELSE 0 END  AS goal3_met,

    shifts_created,
    templates_applied,
    punch_ins

FROM activity_counts;

-- Checking it all lines up with the Task 1 numbers

SELECT COUNT(*) AS total_orgs FROM fct_trial_goals;  -- 966 orgs, one row each

SELECT
    SUM(goal1_met) AS goal1_orgs,   -- 563
    SUM(goal2_met) AS goal2_orgs,   -- 108
    SUM(goal3_met) AS goal3_orgs    -- 211
FROM fct_trial_goals;


-- SECTION 5: MARTS LAYER — fct_trial_activation

-- This is the second table the brief asked for and the
-- final output of the entire model.
--
-- An org only gets marked as Trial Activated if they
-- completed all three goals. Missing even one disqualifies
-- them. The logic is intentionally strict, partial
-- engagement isn't enough. An org that scheduled shifts
-- AND used templates AND had staff clock in is an org
-- that genuinely embedded the product into how they work.
-- That's what we're trying to capture.
--
-- I included activated_at because the brief asked for it.
-- Ideally this would be the exact timestamp when the final
-- goal was crossed, but since goals are tracked at the org
-- level rather than individual event level, trial_end is
-- the closest approximation available in this dataset.

DROP VIEW IF EXISTS fct_trial_activation;
GO

CREATE VIEW fct_trial_activation AS

SELECT
    organization_id,
    trial_start,
    trial_end,
    converted,
    converted_at,

    -- keeping the individual goal flags visible here so
    -- anyone reading this table can see the full picture and
    -- not just whether the org activated but exactly which
    -- goals they did and didn't complete

    goal1_met,
    goal2_met,
    goal3_met,

    -- all three goals met = Trial Activated
    -- one miss anywhere = not activated

    CASE
        WHEN goal1_met = 1
         AND goal2_met = 1
         AND goal3_met = 1 THEN 1
        ELSE 0
    END AS trial_activated,

      
    -- only filled in for orgs that actually activated,
    -- everyone else gets NULL

    CASE
        WHEN goal1_met = 1
         AND goal2_met = 1
         AND goal3_met = 1 THEN trial_end
        ELSE NULL
    END AS activated_at

FROM fct_trial_goals;
GO

-- Confirming the final numbers are right
SELECT COUNT(*) AS total_orgs FROM fct_trial_activation;  -- 966

-- 56 orgs activated = 5.8% activation rate

SELECT
    SUM(trial_activated) AS activated_orgs,
    CAST(SUM(trial_activated) AS FLOAT) / COUNT(*) * 100 AS activation_rate_pct
FROM fct_trial_activation;

-- This is the validation that matters most: orgs that
-- activated converted at 6.3% vs 5.7% for those that didn't.
-- The gap is small but points in the right direction,
-- the goals are picking up something real about product
-- engagement that connects to conversion.

SELECT
    converted,
    COUNT(*) AS total_orgs,
    SUM(trial_activated) AS activated_orgs,
    CAST(SUM(trial_activated) AS FLOAT) / COUNT(*) * 100 AS activation_rate_pct
FROM fct_trial_activation
GROUP BY converted;