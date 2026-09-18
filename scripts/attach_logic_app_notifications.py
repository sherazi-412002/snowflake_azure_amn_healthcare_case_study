#!/usr/bin/env python3
"""
Attach Logic App notification WebActivities (WEB_NOTIFY_SUCCESS and WEB_NOTIFY_FAILURE)
to all ADF pipelines in adf-amn-dev-ionqqq.
"""

import json
import os
import subprocess
import tempfile

RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "rg-amn-dev-data")
FACTORY_NAME = os.environ.get("FACTORY_NAME", "adf-amn-dev-ionqqq")
LOGIC_APP_URL = os.environ.get("LOGIC_APP_URL", "https://<LOGIC_APP_ENDPOINT>/invoke")



def make_web_notify_activities(pipeline_name, success_depends_on, failure_depends_on):
    success_act = {
        "name": "WEB_NOTIFY_SUCCESS",
        "type": "WebActivity",
        "dependsOn": success_depends_on,
        "policy": {
            "timeout": "00:01:00",
            "retry": 1,
            "retryIntervalInSeconds": 30,
            "secureInput": False,
            "secureOutput": False
        },
        "userProperties": [],
        "typeProperties": {
            "method": "POST",
            "url": {
                "value": "@pipeline().parameters.logicAppNotifyUrl",
                "type": "Expression"
            },
            "headers": {
                "Content-Type": "application/json"
            },
            "body": {
                "value": f"@concat('{{\"pipeline_name\":\"{pipeline_name}\",\"status\":\"Succeeded\",\"run_id\":\"', pipeline().RunId, '\",\"start_time\":\"', string(pipeline().TriggerTime), '\",\"error_message\":\"\"}}')",
                "type": "Expression"
            }
        }
    }

    failure_act = {
        "name": "WEB_NOTIFY_FAILURE",
        "type": "WebActivity",
        "dependsOn": failure_depends_on,
        "policy": {
            "timeout": "00:01:00",
            "retry": 0,
            "secureInput": False,
            "secureOutput": False
        },
        "userProperties": [],
        "typeProperties": {
            "method": "POST",
            "url": {
                "value": "@pipeline().parameters.logicAppNotifyUrl",
                "type": "Expression"
            },
            "headers": {
                "Content-Type": "application/json"
            },
            "body": {
                "value": f"@concat('{{\"pipeline_name\":\"{pipeline_name}\",\"status\":\"Failed\",\"run_id\":\"', pipeline().RunId, '\",\"start_time\":\"', string(pipeline().TriggerTime), '\",\"error_message\":\"Pipeline execution failed\"}}')",
                "type": "Expression"
            }
        }
    }
    return success_act, failure_act


def get_dependencies_for_pipeline(pipeline_name, activities):
    act_names = [a["name"] for a in activities]

    # Batch copy child pipelines
    if pipeline_name.startswith("PL_COPY_"):
        succ_name = [n for n in act_names if n.endswith("_SUCCEEDED")]
        fail_names = [n for n in act_names if n.endswith("_FAILED")]
        
        succ_dep = [{"activity": n, "dependencyConditions": ["Succeeded"]} for n in succ_name]
        fail_dep = [{"activity": n, "dependencyConditions": ["Succeeded", "Failed"]} for n in fail_names] if fail_names else []
        return succ_dep, fail_dep

    # Incremental child pipelines
    if pipeline_name in ["PL_INCREMENTAL_STAFFING_REQUESTS", "PL_INCREMENTAL_CANDIDATES", "PL_INCREMENTAL_SCHEDULES", "PL_INCREMENTAL_PAYROLL"]:
        if "UPDATE_WATERMARK" in act_names:
            succ_dep = [{"activity": "UPDATE_WATERMARK", "dependencyConditions": ["Succeeded"]}]
            fail_dep = [{"activity": "MERGE_TO_CURATED", "dependencyConditions": ["Failed"]},
                        {"activity": "COPY_CHANGED_ROWS", "dependencyConditions": ["Failed"]}]
            return succ_dep, fail_dep

    # Incremental parent pipeline
    if pipeline_name == "PL_INCREMENTAL_OPERATIONAL_INGEST":
        run_acts = [n for n in act_names if n.startswith("RUN_")]
        succ_dep = [{"activity": n, "dependencyConditions": ["Succeeded"]} for n in run_acts]
        # Failure if any of them fails
        fail_dep = [{"activity": n, "dependencyConditions": ["Failed"]} for n in run_acts]
        return succ_dep, fail_dep

    # File event router
    if pipeline_name == "PL_FILE_EVENT_ROUTER":
        if "ROUTE_LANDING_CSV" in act_names:
            succ_dep = [{"activity": "ROUTE_LANDING_CSV", "dependencyConditions": ["Succeeded"]}]
            fail_dep = [{"activity": "ROUTE_LANDING_CSV", "dependencyConditions": ["Failed"]}]
            return succ_dep, fail_dep

    # API test / Generic fallback: depend on the last activity
    if activities:
        last_act = activities[-1]["name"]
        return ([{"activity": last_act, "dependencyConditions": ["Succeeded"]}],
                [{"activity": last_act, "dependencyConditions": ["Failed"]}])

    return [], []


def update_pipeline(pipeline_data):
    name = pipeline_data["name"]
    activities = pipeline_data.get("activities", [])
    
    # Skip if already attached
    existing_web = [a["name"] for a in activities if a["name"] in ["WEB_NOTIFY_SUCCESS", "WEB_NOTIFY_FAILURE"]]
    if len(existing_web) == 2:
        print(f"Skipping {name}: already has notification activities.")
        return False

    # Filter out partial notification activities if any
    activities = [a for a in activities if a["name"] not in ["WEB_NOTIFY_SUCCESS", "WEB_NOTIFY_FAILURE"]]

    succ_dep, fail_dep = get_dependencies_for_pipeline(name, activities)
    if not succ_dep:
        print(f"Warning: Could not determine dependencies for {name}, skipping.")
        return False

    succ_act, fail_act = make_web_notify_activities(name, succ_dep, fail_dep)
    activities.append(succ_act)
    if fail_dep:
        activities.append(fail_act)

    # Ensure parameters exist
    params = pipeline_data.get("parameters") or {}
    params["logicAppNotifyUrl"] = {
        "type": "string",
        "defaultValue": LOGIC_APP_URL
    }

    pipeline_data["activities"] = activities
    pipeline_data["parameters"] = params
    return True


def main():
    print(f"Fetching pipelines from {FACTORY_NAME} in {RESOURCE_GROUP}...")
    res = subprocess.check_output([
        "az.cmd", "datafactory", "pipeline", "list",
        "--resource-group", RESOURCE_GROUP,
        "--factory-name", FACTORY_NAME,
        "--output", "json"
    ])
    pipelines = json.loads(res)

    for p in pipelines:
        name = p["name"]
        print(f"\nProcessing pipeline: {name}...")
        changed = update_pipeline(p)
        if not changed:
            continue

        # Prepare payload for az datafactory pipeline create
        # Format expects {"properties": {"activities": ..., "parameters": ...}}
        payload = {
            "properties": {
                "activities": p.get("activities", []),
                "parameters": p.get("parameters", {}),
                "variables": p.get("variables", {}),
                "annotations": p.get("annotations", []),
                "concurrency": p.get("concurrency")
            }
        }

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tf:
            json.dump(payload, tf, indent=2)
            temp_path = tf.name

        try:
            print(f"Deploying updated {name} to ADF...")
            subprocess.check_call([
                "az.cmd", "datafactory", "pipeline", "create",
                "--resource-group", RESOURCE_GROUP,
                "--factory-name", FACTORY_NAME,
                "--name", name,
                "--pipeline", f"@{temp_path}"
            ])
            print(f"Successfully updated {name} in ADF.")
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    print("\nAll pipelines successfully processed and deployed!")


if __name__ == "__main__":
    main()
