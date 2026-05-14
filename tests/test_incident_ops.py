from incident_ops import (
    IncidentEvent,
    IncidentPolicy,
    build_incident_log,
    build_status_report,
    decide_action,
)


def incident_event(**overrides):
    values = {
        "phase": "dry-run",
        "trigger": "timeout in collector",
        "action": "collect_logs",
        "monitored_workflow": "daily dry-run",
        "symptom": "collector timed out",
        "impact": "dry-run cannot advance",
        "pre_evidence": "before: timeout",
        "post_evidence": "after: logs captured",
        "remaining_risk": "root cause still under review",
    }
    values.update(overrides)
    return IncidentEvent(**values)


def test_safe_dry_run_diagnostic_is_auto_allowed():
    event = incident_event()

    decision = decide_action(event, IncidentPolicy())

    assert decision["action_class"] == "observe"
    assert decision["decision"] == "auto_allowed"


def test_guarded_recovery_is_allowed_once_then_requires_approval():
    policy = IncidentPolicy(guarded_recover="allow_once")
    first = incident_event(
        trigger="sandbox token expired",
        action="refresh_sandbox_token",
        previous_action_count=0,
    )
    second = incident_event(
        trigger="sandbox token expired",
        action="refresh_sandbox_token",
        previous_action_count=1,
    )

    assert decide_action(first, policy)["decision"] == "auto_allowed_once"
    assert decide_action(second, policy)["decision"] == "ask_required"


def test_trading_side_effect_is_blocked_in_field_test():
    event = incident_event(
        phase="field-test",
        trigger="strategy wants live order",
        action="place_order",
    )

    decision = decide_action(event, IncidentPolicy(mode="field-test"))

    assert decision["action_class"] == "blocked"
    assert decision["decision"] == "blocked"


def test_ui_field_test_log_requires_ui_evidence():
    event = incident_event(
        phase="field-test",
        trigger="blank operator dashboard",
        action="capture_screenshot",
        ui=True,
        ui_evidence={"route": "/ops"},
    )

    log = build_incident_log(event, IncidentPolicy(mode="field-test"))

    assert log["valid"] is False
    assert "viewport" in log["missing_ui_evidence"]
    assert "ui_state" in log["missing_ui_evidence"]
    assert "next_action_possible" in log["missing_ui_evidence"]
    assert log["next_approval_boundary"] == "ask_user"


def test_ui_field_test_log_accepts_complete_ui_evidence():
    event = incident_event(
        phase="field-test",
        trigger="operator could not continue workflow",
        action="capture_screenshot",
        ui=True,
        ui_evidence={
            "route": "/ops/orders",
            "viewport": "desktop-1440x900",
            "screenshot": ".omx/incidents/shot.png",
            "console_status": "no errors",
            "network_status": "GET /readonly/orders 200",
            "operator_step": "review dry-run signal",
            "ui_state": "success",
            "next_action_possible": "yes",
        },
    )

    log = build_incident_log(event, IncidentPolicy(mode="field-test"))

    assert log["valid"] is True
    assert log["next_approval_boundary"] == "continue"
    assert log["evidence"]["ui"]["ui_state"] == "success"
    assert log["evidence"]["ui"]["next_action_possible"] == "yes"


def test_external_api_log_preserves_sandbox_and_real_network_evidence():
    event = incident_event(
        phase="dry-run",
        trigger="external API connection refused in sandbox",
        action="compare_sandbox_real_network",
        sandbox_evidence="sandbox ECONNREFUSED",
        real_network_evidence="approved read-only path returned 200",
    )

    log = build_incident_log(event, IncidentPolicy())

    assert log["decision"] == "auto_allowed"
    assert log["evidence"]["sandbox"] == "sandbox ECONNREFUSED"
    assert log["evidence"]["real_network"] == "approved read-only path returned 200"


def test_policy_carries_project_specific_reporting_intervals():
    policy = IncidentPolicy(
        heartbeat_interval_seconds=60,
        quiet_interval_seconds=600,
        incident_escalation_interval_seconds=120,
    )
    event = incident_event(
        phase="operational-rehearsal",
        trigger="long-running watch heartbeat",
        action="classify_failure",
    )

    log = build_incident_log(event, policy)

    assert log["reporting"]["heartbeat_interval_seconds"] == 60
    assert log["reporting"]["quiet_interval_seconds"] == 600
    assert log["reporting"]["incident_escalation_interval_seconds"] == 120


def test_incident_log_contains_full_contract_fields():
    event = incident_event(
        ui=True,
        ui_evidence={
            "route": "/ops",
            "viewport": "desktop",
            "screenshot": ".omx/incidents/shot.png",
            "console_status": "no errors",
            "network_status": "GET /readonly/orders 200",
            "operator_step": "review signal",
            "ui_state": "success",
            "next_action_possible": "yes",
        },
    )

    log = build_incident_log(event, IncidentPolicy())

    assert "T" in log["timestamp"]
    assert log["phase"] == "dry-run"
    assert log["trigger"] == "timeout in collector"
    assert log["severity"] == "medium"
    assert log["monitored_workflow"] == "daily dry-run"
    assert log["symptom"] == "collector timed out"
    assert log["impact"] == "dry-run cannot advance"
    assert log["action_class"] == "observe"
    assert log["decision"] == "auto_allowed"
    assert log["exact_automatic_action"] == "collect_logs"
    assert log["evidence"]["pre_action"] == "before: timeout"
    assert log["evidence"]["post_action"] == "after: logs captured"
    assert log["evidence"]["ui"]["route"] == "/ops"
    assert log["evidence"]["ui"]["ui_state"] == "success"
    assert log["reporting"]["heartbeat_interval_seconds"] == 900
    assert log["reporting"]["quiet_interval_seconds"] == 1800
    assert log["reporting"]["incident_escalation_interval_seconds"] == 300
    assert log["next_approval_boundary"] == "continue"
    assert log["remaining_risk"] == "root cause still under review"


def test_secret_like_evidence_is_redacted_from_incident_log():
    event = incident_event(
        pre_evidence="token=abc123 account_number=123456789 Bearer rawtoken",
        post_evidence="authorization: Bearer authrawtoken api_key=key123",
        sandbox_evidence="password=secret client_secret=clientsecret",
        ui_evidence={
            "route": "/ops?token=abc",
            "viewport": "desktop",
            "screenshot": ".omx/incidents/shot.png",
            "console_status": "secret=abc",
            "network_status": "ok",
            "operator_step": "review",
            "ui_state": "success",
            "next_action_possible": "yes",
        },
        ui=True,
    )

    log = build_incident_log(event, IncidentPolicy())

    flattened = str(log["evidence"])
    assert "abc123" not in flattened
    assert "123456789" not in flattened
    assert "rawtoken" not in flattened
    assert "authrawtoken" not in flattened
    assert "Bearer authrawtoken" not in flattened
    assert "key123" not in flattened
    assert "clientsecret" not in flattened
    assert "secret=abc" not in flattened
    assert "[REDACTED]" in flattened


def test_secret_redaction_handles_comma_separated_tokens():
    event = incident_event(
        pre_evidence="api_key=secretA,secretB token=tokenA,tokenB",
        post_evidence="client_secret=clientA,clientB",
    )

    log = build_incident_log(event, IncidentPolicy())

    flattened = str(log["evidence"])
    assert "secretA" not in flattened
    assert "secretB" not in flattened
    assert "tokenA" not in flattened
    assert "tokenB" not in flattened
    assert "clientA" not in flattened
    assert "clientB" not in flattened


def test_unknown_action_is_blocked_by_default():
    event = incident_event(action="unknown_live_mutation")

    decision = decide_action(event, IncidentPolicy())

    assert decision["action_class"] == "blocked"
    assert decision["decision"] == "blocked"


def test_policy_fields_can_tighten_automatic_action_decisions():
    event = incident_event(action="restart_local_service")

    decision = decide_action(event, IncidentPolicy(recoverable="ask"))

    assert decision["action_class"] == "safe_recover"
    assert decision["decision"] == "ask_required"


def test_sensitive_actions_require_approval_even_if_policy_is_misconfigured():
    for action in ["write_production_db", "change_credentials", "deploy_production"]:
        event = incident_event(action=action)

        decision = decide_action(event, IncidentPolicy(sensitive="allow"))

        assert decision["action_class"] == "ask_required"
        assert decision["decision"] == "ask_required"


def test_status_report_contains_periodic_monitoring_contract():
    report = build_status_report(
        phase="field-test",
        monitored_surface="operator UI and read-only broker API",
        last_successful_check="09:40 health/read-only orders ok",
        active_incident_count=1,
        automatic_actions_taken=["capture_screenshot"],
        blocked_or_approval_actions=["place_order"],
        next_check="09:45",
        policy=IncidentPolicy(
            heartbeat_interval_seconds=60,
            quiet_interval_seconds=300,
            incident_escalation_interval_seconds=30,
        ),
        ui_status={
            "route": "/ops/orders",
            "viewport": "desktop",
            "console_status": "no errors",
            "network_status": "GET /readonly/orders 200",
            "next_action_possible": "yes",
        },
    )

    assert report["phase"] == "field-test"
    assert report["monitored_surface"] == "operator UI and read-only broker API"
    assert report["active_incident_count"] == 1
    assert report["automatic_actions_taken"] == ["capture_screenshot"]
    assert report["blocked_or_approval_actions"] == ["place_order"]
    assert report["next_check"] == "09:45"
    assert report["reporting"]["incident_escalation_interval_seconds"] == 30
    assert report["ui_status"]["next_action_possible"] == "yes"
