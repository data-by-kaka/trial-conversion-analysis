# Splendor Analytics Trial Activation

---

## Project Overview

Only 1 in 5 organisations trialling the Splendor platform convert to paying customers. This project tackles that problem from three angles: defining what a successful trial actually looks like in behavioural terms, building the data infrastructure to track it at scale, and producing the descriptive analytics that show where the product is winning and where it is losing users.

The dataset contains 170,526 raw event log entries across 966 unique organisations, each on a 30-day trial. Every row represents one in-app action taken by an organisation, timestamped and linked to their trial window and conversion outcome.

---

## Tools and Technologies
**Python** (pandas, numpy, matplotlib, seaborn, scipy) was used for all exploratory analysis, statistical testing, and data visualisation across Tasks 1 and 3.

**SQL Server (MySQL)** was used for Task 2 to build the structured data warehouse model, with views constructed in layers from raw ingestion through to the final activation fact tables.

**Jupyter Notebook** served as the working environment for both Python tasks, keeping code, commentary, and charts together in one readable document.

---

## Project Objectives
Explore and clean the raw event data to make it analysis-ready
Identify which in-app behaviours are associated with conversion
Define measurable Trial Goals that signal genuine product adoption
Build a SQL-based data warehouse model to track those goals at scale
Run descriptive analytics to surface actionable insights for the product team

---
## Repository Structure

splendor-trial-activation/
│
├── data/
│   └── DA_task.csv                  ← Raw event log (170,526 rows)
│
├── Notebook/
│   └── TASK 1.ipynb                 ← EDA, conversion analysis, goal definition
│   └── TASK 3.ipynb                  ← Descriptive analytics and product metrics
├── SQL/
│   └── TASK 2.sql                   ← Staging and mart layer SQL models
|
|
├── requirements.txt
└──  README.md


## Dataset Description

The dataset contains behavioural event logs for organisations that started trials between January and March.

| Column          | Description                             |
| --------------- | --------------------------------------- |
| organization_id | Unique identifier for each organisation |
| activity_name   | Action performed in the product         |
| timestamp       | Time of activity                        |
| converted       | Whether the organisation converted      |
| converted_at    | Time of conversion                      |
| trial_start     | Trial start date                        |
| trial_end       | Trial end date                          |

Raw shape: 170,526 rows x 7 columns. After removing 67,631 exact duplicate rows and filtering to events that fell within each organisation's trial window, the clean dataset contained 102,895 rows across 966 unique organisations. Of those, 206 converted (21.3%) and 760 did not.

----

##  Task 1: Exploratory Data Analysis and Trial Goal Definition

**Data Cleaning**

The raw data required three cleaning steps before any analysis was possible. All four date columns were stored as plain text and needed to be parsed into proper datetime objects. After that, 67,631 exact duplicate rows were removed using a deduplication step that retained only one copy of each unique event. Finally, any events that occurred outside an organisation's 30-day trial window were filtered out, since those actions do not reflect trial behaviour. The result was a clean event log of 102,895 rows.

**Org-Level Summary**

With the clean event log in place, the analysis collapsed all individual events into a single summary row per organisation. This produced a 966-row table capturing metrics like total events, unique activities tried, days with any activity, the day they first engaged, the day they last engaged, and a modules used score across the five core product areas.

**Conversion Driver Analysis: What the Data Said**
The first instinct in a problem like this is to ask whether more active organisations are more likely to convert. To test that, Mann-Whitney U tests were run across six engagement metrics: total events, unique activities, days active, first event day, last event day, and modules used. Every single p-value came back above 0.05, with the lowest being 0.30. The conclusion was unambiguous: converted and non-converted organisations behaved in almost identical ways in terms of general engagement volume. How much they used the platform did not predict whether they became customers.

This finding shifted the analysis to a different question entirely: not how much, but which specific activities.

**Activity-Level Conversion Rates**
For each of the 28 activities in the dataset, the analysis calculated the conversion rate among organisations that used that activity and compared it to the 21.3% baseline. A usage gap analysis was also run, comparing how frequently converted versus non-converted organisations engaged with each activity.

The activities that stood out were:

Scheduling.Template.ApplyModal.Applied showed a 25.0% conversion rate, nearly 4 percentage points above baseline, and a usage gap of +2.4 percentage points between converters and non-converters. Applying a template is a deliberate, efficiency-seeking behaviour. It signals an organisation is not just testing the product but thinking about how to work faster with it.

Scheduling.Shift.Created was the most widely used activity in the entire platform, adopted by 848 of 966 organisations. On its own, creating a single shift does not strongly predict conversion because almost everyone does it. But organisations that created at least three shifts showed higher conversion rates, indicating that a threshold of genuine scheduling work, rather than mere exploration, is the meaningful signal.

PunchClock.PunchedIn showed a 22.7% conversion rate and a positive usage gap of +1.9 percentage points. A clock-in event means the platform has moved beyond the manager's scheduling tool and into actual daily staff operations. That is a fundamentally different level of product commitment.


**Defined Trial Goals**
Based on this analysis, three Trial Goals were defined:

**Goal 1:** Core Scheduling Activated. The organisation creates at least 3 shifts during the trial. One or two could be exploratory. Three or more signals they are building a real working schedule.

**Goal 2:** Scheduling Depth Reached. The organisation applies at least one shift template. This is a power-user behaviour that indicates they are optimising their workflow, not just exploring the interface.

**Goal 3:** Time and Attendance Activated. At least one team member clocks in using PunchClock. This is the moment the product stops being a planning tool and becomes part of the daily operational routine.

An organisation achieves Trial Activation when it completes all three goals within its 30-day trial window.

**Validation**


| Metric                         | Result                     |
| ---------------------------    | ---------------------------|
| Goal 1 completion rate         |  58.3% of orgs (563)       |
| Goal 2 completion rate         | 11.2% of orgs (108)        |
| Goal 3 completion rate         | 21.8% of orgs (211)        |
| Trial Activation rate          | 5.8% of orgs (56)          |
| Converters who activated       | 6.3%                       |
| Non-converters who activated   | 5.7%                       |

Organisations that completed all three goals converted at a higher rate than those that did not. The gap is modest, and that is worth being honest about. The data simply does not produce a clean, dramatic separation between the two groups. Converted and non-converted organisations used the platform in strikingly similar ways. What drives conversion may partly live outside the product itself, in sales conversations, pricing timing, or organisational urgency, none of which the event log can capture. These three goals represent the strongest behavioural hypothesis the data supports and should be treated as a starting point to monitor, test, and refine as more trial cohorts accumulate.


## Task 2: SQL Data Warehouse Models
**SQL:** task.sql

**Architecture**

Rather than building one large query, the model was structured in four clean layers, each with a single responsibility.

raw_events            ← Raw layer: DA_task.csv loaded as-is (170,526 rows)
      ↓
stg_events            ← Staging layer: cast, deduplicated, filtered (102,895 rows)
      ↓
fct_trial_goals       ← Mart layer: one row per org, goal flags (966 rows)
      ↓
fct_trial_activation  ← Mart layer: trial_activated flag and activated_at (966 rows)

**raw_events** stores the data exactly as it arrived. Date columns were kept as VARCHAR during import because SQL Server's conversion engine threw errors on the source format. Cleaning happens downstream.

**stg_events** is a view that performs all three cleaning steps: converting date strings to DATETIME2 using TRY_CONVERT (which returns NULL rather than crashing on malformed values), removing duplicates using ROW_NUMBER() partitioned over all identifying columns, and filtering to events within each organisation's trial window.

**fct_trial_goals** is the first mart table. It collapses the clean event log to one row per organisation and applies the three goal thresholds as binary flags. The raw activity counts are preserved alongside the flags so anyone auditing the data can see exactly how each flag was determined.

**fct_trial_activation** is the final output table. It combines all three goal flags with a single trial_activated flag and an activated_at timestamp. Only organisations that meet all three goals receive a non-null activated_at value.

**fct_trial_goals Schema***

| Column              | Description                                    |
| --------------------| ----------------------------------             |
| organization_id     | Unique org identifier                          |
| goal1_met	1         | if Scheduling.Shift.Created >= 3, else 0       |
| goal2_met	1         | if Template.ApplyModal.Applied >= 1, else 0    |
| goal3_met	1         | if PunchClock.PunchedIn >= 1, else 0           |
| shifts_created      | Raw count for auditability                     |
| templates_applied   | Raw count for auditability                     |
| punch_ins	          | Raw count for auditability                     |

**fct_trial_activation Schema**

| Column	          | Description
| ------------------| --------------------------------------- |
| organization_id	  |  Unique org identifier                  |
| trial_activated	1 | if all 3 goals met, else 0              |
| activated_at	    | trial_end if activated, NULL otherwise  |


## Task 3: Descriptive Analytics and Product Metrics
**Notebook:** 02_Task.ipynb

This task runs structured descriptive analyses across six areas: conversion rate, time to convert, goal funnel, feature adoption, engagement depth, and product metrics. The findings are translated into concrete recommendations for the product team.

**Conversion Rate**
The overall conversion rate was 21.3%, consistent with the 1-in-5 figure stated in the brief. Breaking this down by trial cohort revealed an important trend. The January cohort converted at 23.0% and February at 22.8%, both comfortably above average. The March cohort dropped to 18.2%, a decline of nearly 5 percentage points in a single month. This cohort-level drop is the clearest early warning signal in the dataset and warrants immediate investigation.

| Cohort	       | Organisations	  | Conversion Rate    |
| ---------------| ---------------- |------------------- |
| January  2024  | 	305	            | 23.0%              |
| February 2024  | 	347	            | 22.8%              |
| March    2024  | 	314	            | 18.2%              |
| Overall        |	966	            | 21.3%              |

**Time to Convert**
Of the 206 organisations that converted, the analysis measured how many days elapsed between their trial start date and their conversion date. The distribution showed that conversions were spread across the full trial window rather than clustering early, suggesting that most organisations take time to evaluate before committing. This has implications for when sales follow-ups and in-app nudges should be triggered.

**Trial Goal Funnel**
The funnel analysis shows exactly where organisations drop off on the path to Trial Activation.

| Stage                           | Organisations	  | % of Total	| Drop-off        |
| --------------------------------| ----------------|-------------|---------------- |
| Started Trial	                  | 966	            | 100.0%	    | --              |
| Goal 1 Met (3+ shifts)          | 563	            | 58.3%	      | -403 (41.7%)    |
| Goal 2 Met (template applied)	  | 108	            | 11.2%       | 	-455 (80.8%)  |
| Goal 3 Met (punched in)	        | 211	            | 21.8%      	| -352 (62.5%)    |
| Trial Activated (all 3)	        | 56              | 5.8%        | 	--            |

The most striking number here is the drop between Goal 1 and Goal 2. Of the 563 organisations that created 3 or more shifts, only 108 ever applied a shift template, an 80.8% drop-off between two features that live in the same module. This is the single biggest opportunity in the entire activation funnel.

**Feature and Module Adoption**
Adoption rate is defined as the percentage of organisations that used a given activity or module at least once during their trial. The gap between Scheduling and everything else is the defining feature of the adoption landscape.

| Module	        | Organisations	| Adoption Rate |
| ----------------| --------------|---------------|
| Scheduling	    | 852	          | 88.2%         |
| PunchClock	    | 211	          | 21.8%         |
| Communication	  | 145	          | 15.0%         |
| Absence	        | 40	          | 4.1%          |
| Timesheets	    | 10	          | 1.0%          |

Scheduling is the front door of the product. Almost every organisation that starts a trial uses it. Everything else is an expansion opportunity that the vast majority of trialling organisations never reach. Timesheets at 1.0% is particularly striking as it is effectively invisible during the trial period.

**Engagement Depth and Stickiness**
Stickiness was measured as the proportion of trial days on which an organisation logged any activity. A score of 1.0 means they were active every single day of their trial. A score of 0.1 means they showed up on roughly 3 days out of 30.

| Stickiness Band	        | Organisations	  | % of Total         |
| ------------------------| --------------  |------------------- |
| Low (< 0.2)	            | 815	            | 84.4%              |
| Moderate (0.2 to 0.5)	  | 56	            |  5.8%              |
| Very Sticky (>= 0.5)    | 95	            |  9.8%              |

The overall median stickiness was 0.032, meaning the typical organisation was active on roughly 1 day out of every 30. Critically, converters and non-converters had identical median stickiness scores. This confirms the Task 1 finding that frequency of engagement does not separate those who convert from those who do not. Workforce management is not a daily-use product for most organisations. They dip in when rosters need building and step back out. This is normal behaviour for the category, not a product failure. The 95 highly sticky organisations, those active on more than half their trial days, represent the product's most engaged segment and deserve dedicated study.

**Product Metrics Summary**
| Metric	                          | Value               |
| ----------------------------------| --------------------|
| Overall conversion rate	          | 21.3%               |
| Trial activation rate	            | 5.8%                |
| Activated then converted	        | 23.2%               |
| Not activated then converted	    | 21.2%               |
| Goal 1 completion rate	          | 58.3%               |
| Goal 2 completion rate	          | 11.2%               |
| Goal 3 completion rate	          | 21.8%               |
| Scheduling module adoption	      | 88.2%               |
| PunchClock module adoption	      | 21.8%               |
| Timesheets module adoption	      | 1.0%                |
| Orgs with low stickiness (< 0.2)	| 84.4%               |
| Highly sticky orgs (>= 0.5)	      | 9.8% (95 orgs)      |
| March cohort conversion rate	    | 18.2%               |


Organisations that achieved Trial Activation converted at 23.2% compared to 21.2% for those that did not. The gap is real but modest. As the activation model matures and more cohorts accumulate, this gap is expected to widen as the goal definitions are refined.

**Recommendations**
**Fix the Goal 2 bottleneck as this is the biggest opportunity in the funnel.** Only 11.2% of organisations ever apply a shift template, despite 58.3% creating enough shifts to qualify for Goal 1. Roughly 80% of organisations who have demonstrated real scheduling intent never discover one of the platform's most time-saving features. An in-app nudge triggered after the third shift is created, highlighting templates as a natural next step, could improve Goal 2 completion substantially without requiring any changes to the feature itself.

**Accelerate PunchClock activation earlier in the trial.** Only 21.8% of trialling organisations ever have a team member clock in. This is the feature that transitions the platform from a manager's planning tool into something the whole team uses daily. Building a guided invite-your-team prompt into the onboarding flow, triggered early in the trial rather than left to chance, could shift this number meaningfully.

**Investigate the March cohort drop urgently.** A conversion rate of 18.2% against a 23% baseline is a signal worth taking seriously. The event data alone cannot explain it, but cross-referencing against CRM data, sales activity, and any product or pricing changes from that period should surface the cause quickly. Monitoring the April and May cohorts closely as they mature will confirm whether March was an anomaly or the start of a trend.

**Design onboarding around Scheduling first, then expand.** With 88.2% adoption, Scheduling is the product's undisputed anchor module. Onboarding flows, tooltips, and in-app guidance should treat Scheduling as the entry point and use it as a launchpad to introduce PunchClock, Communication, and other modules progressively. The current data suggests most organisations never naturally discover these modules on their own.

**Do not optimise for daily engagement, optimise for depth.** Stickiness is low across the board and identical between converters and non-converters. Trying to increase daily login frequency is unlikely to improve conversion. Instead the focus should be on depth of use per session, whether organisations are completing meaningful workflows when they do show up, rather than how often they appear.

**Study the 95 highly sticky organisations.** They represent the product's power users and the clearest picture of what genuine embedded usage looks like. Analysing their activation sequences, the order in which they discovered features, how quickly they moved from scheduling into PunchClock, and what their first week looked like would provide a behavioural blueprint that could directly inform onboarding design for all future trialists.

**Revisit Trial Goals quarterly.** The current goals are the strongest hypothesis the available data supports, but they were built on a single snapshot of the user base. As more trial cohorts accumulate, the thresholds and activity selections that define the three goals should be revalidated. Quarterly recalibration will ensure the goals remain meaningful as the product and its users evolve.


