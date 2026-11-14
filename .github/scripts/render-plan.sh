#!/usr/bin/env bash
# Render a Terraform plan as a Markdown PR comment.
#
# Usage: render-plan.sh <env> <plan-outcome> <plan.json> <plan.txt> <out.md>
#   plan-outcome: GitHub step outcome of `terraform plan` (success|failure)
set -euo pipefail

env_name="$1"
outcome="$2"
plan_json="$3"
plan_txt="$4"
out="$5"

marker="<!-- laidir-plan:${env_name} -->"
max_plan_chars=55000 # GitHub comments are capped at 65,536 characters

{
  echo "$marker"
  echo "## Terraform plan: \`${env_name}\`"
  echo

  if [[ "$outcome" != "success" || ! -s "$plan_json" ]]; then
    echo "❌ **Plan failed.** See the job log for details."
    echo
    if [[ -s "$plan_txt" ]]; then
      echo '<details><summary>Output</summary>'
      echo
      echo '```'
      head -c "$max_plan_chars" "$plan_txt"
      echo '```'
      echo '</details>'
    fi
  else
    # Ignore no-op and read actions; classify the rest.
    changes=$(jq -c '[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])]' "$plan_json")
    count() { jq "[.[] | select(.change.actions == $1)] | length" <<<"$changes"; }

    add=$(count '["create"]')
    update=$(count '["update"]')
    destroy=$(count '["delete"]')
    replace=$(jq '[.[] | select((.change.actions | sort) == ["create","delete"])] | length' <<<"$changes")

    if [[ "$(jq length <<<"$changes")" -eq 0 ]]; then
      echo "✅ **No changes.** Infrastructure matches the configuration."
    else
      if (( destroy > 0 || replace > 0 )); then
        echo "> [!WARNING]"
        echo "> This plan **destroys or replaces** resources. Review carefully before merging."
        echo
      fi

      echo "| ➕ Add | ✏️ Change | ♻️ Replace | 🗑️ Destroy |"
      echo "|:---:|:---:|:---:|:---:|"
      echo "| ${add} | ${update} | ${replace} | ${destroy} |"
      echo
      echo "| | Resource |"
      echo "|---|---|"
      jq -r '
        .[] |
        (.change.actions | sort) as $a |
        (if $a == ["create"] then "➕"
         elif $a == ["update"] then "✏️"
         elif $a == ["delete"] then "🗑️"
         elif $a == ["create","delete"] then "♻️"
         else "•" end) as $icon |
        "| \($icon) | `\(.address)` |"
      ' <<<"$changes"
    fi

    echo
    echo '<details><summary>Full plan</summary>'
    echo
    echo '```hcl'
    head -c "$max_plan_chars" "$plan_txt"
    if (( $(wc -c <"$plan_txt") > max_plan_chars )); then
      echo
      echo "... truncated, see the job log for the full plan."
    fi
    echo '```'
    echo '</details>'
  fi

  echo
  echo "<sub>Commit ${GITHUB_SHA:-local} · run [#${GITHUB_RUN_NUMBER:-0}](${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-})</sub>"
} >"$out"
