---
name: plan-to-dex
description: 'Use when running an already-hardened Superpowers implementation plan through the dex orchestrator (codex backend) instead of the Ralph loop. Triggers on: convert plan to dex, plan to dex, dex from plan, run plan with dex, plan-to-dex.'
user-invocable: true
---

# Plan-to-Dex Runner

Translate a Superpowers implementation plan into a [dex](https://github.com/francescoalemanno/dex)-compatible `plan.md`, import it, and run dex's autonomous loop (`apply` → `review`) end to end with **codex** as the fixed backend.

The plan is the **source of truth**. Do NOT re-interview the user, regenerate requirements, or let dex re-plan via `dex plan`.

**Backend is fixed to codex** (`--cli codex`): the skill never asks which backend, never sets `--model`, and never writes `.dex/config.json`. The model is whatever the user's codex install defaults to.

---

## The Job

1. Locate and validate the implementation plan
2. Translate plan tasks into a dex checkbox-group `plan.md`
3. Preflight (dex + codex on PATH; branch guard)
4. One confirmation before the autonomous chain
5. Run `dex import` → `dex apply --cli codex` → `dex review --cli codex`
6. Show the handoff report

**Output file:** `tasks/dex-plan.md` — the translated plan, then installed by `dex import` into `.dex/plan.md`.

---

## Step 1: Locate the Plan

<!-- filled in Task 3 -->

## Step 2: Validate the Plan

<!-- filled in Task 3 -->

## Step 3: Translate to dex plan.md

<!-- filled in Task 4 -->

## Step 4: Preflight Checks

<!-- filled in Task 5 -->

## Step 5: Confirm

<!-- filled in Task 5 -->

## Step 6: Run the dex Chain

<!-- filled in Task 5 -->

## Step 7: Handoff Report

<!-- filled in Task 5 -->
