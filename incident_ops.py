from dataclasses import dataclass, field
from datetime import datetime, timezone
import re


ACTION_CLASSES = {
    "collect_logs": "observe",
    "capture_screenshot": "observe",
    "classify_failure": "diagnose",
    "retry_readonly_once": "diagnose",
    "compare_sandbox_real_network": "diagnose",
    "restart_local_service": "safe_recover",
    "clear_local_cache": "safe_recover",
    "refresh_ui_session": "safe_recover",
    "refresh_sandbox_token": "guarded_recover",
    "regenerate_fixture": "guarded_recover",
    "write_production_db": "ask_required",
    "change_credentials": "ask_required",
    "deploy_production": "ask_required",
    "place_order": "blocked",
    "cancel_order": "blocked",
    "modify_position": "blocked",
}

ACTION_CLASS_POLICY_FIELDS = {
    "observe": "safe",
    "diagnose": "safe",
    "safe_recover": "recoverable",
    "guarded_recover": "guarded_recover",
    "ask_required": "sensitive",
    "blocked": "dangerous",
}

SECRET_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"(?P<prefix>authorization\s*[:=]\s*Bearer\s+)[A-Za-z0-9._~+/=-]+",
        r"Bearer\s+[A-Za-z0-9._~+/=-]+",
        r"(?P<prefix>(?:api[_-]?key|client[_-]?secret|token|secret|password|credential|authorization)\s*[:=]\s*)[^,\s]+(?:,[^,\s]+)*",
        r"(?P<prefix>account(?:[_ -]?number)?\s*[:=]\s*)\d{6,}",
    ]
]


@dataclass(frozen=True)
class IncidentPolicy:
    mode: str = "dry-run"
    safe: str = "allow"
    recoverable: str = "allow"
    guarded_recover: str = "allow_once"
    sensitive: str = "ask"
    dangerous: str = "block"
    heartbeat_interval_seconds: int = 900
    quiet_interval_seconds: int = 1800
    incident_escalation_interval_seconds: int = 300


@dataclass(frozen=True)
class IncidentEvent:
    phase: str
    trigger: str
    action: str
    monitored_workflow: str
    symptom: str
    impact: str
    pre_evidence: str
    post_evidence: str
    remaining_risk: str
    severity: str = "medium"
    ui: bool = False
    previous_action_count: int = 0
    sandbox_evidence: str | None = None
    real_network_evidence: str | None = None
    ui_evidence: dict[str, str] = field(default_factory=dict)


def classify_action(action: str) -> str:
    return ACTION_CLASSES.get(action, "blocked")


def decide_action(event: IncidentEvent, policy: IncidentPolicy) -> dict[str, str]:
    action_class = classify_action(event.action)
    policy_value = getattr(policy, ACTION_CLASS_POLICY_FIELDS[action_class])

    if action_class in {"observe", "diagnose"} and policy_value == "allow":
        decision = "auto_allowed"
    elif action_class == "safe_recover" and policy_value == "allow":
        decision = "auto_allowed"
    elif action_class == "guarded_recover" and policy_value == "allow_once":
        decision = (
            "auto_allowed_once"
            if event.previous_action_count == 0
            else "ask_required"
        )
    elif action_class == "guarded_recover" and policy_value == "allow":
        decision = "auto_allowed"
    elif action_class == "ask_required":
        decision = "ask_required"
    elif action_class == "blocked":
        decision = "ask_required" if policy_value == "ask" else "blocked"
    else:
        decision = "ask_required"

    return {
        "action": event.action,
        "action_class": action_class,
        "decision": decision,
        "policy_value": policy_value,
        "reason": reason_for_decision(action_class, decision),
    }


def reason_for_decision(action_class: str, decision: str) -> str:
    if decision == "auto_allowed":
        return "safe reversible incident response"
    if decision == "auto_allowed_once":
        return "guarded recovery allowed once by policy"
    if action_class == "blocked":
        return "external side effect is blocked during dry-run/field-test"
    return "user approval required before side-effectful or sensitive action"


def validate_ui_evidence(event: IncidentEvent) -> list[str]:
    if not event.ui:
        return []

    required = [
        "route",
        "viewport",
        "screenshot",
        "console_status",
        "network_status",
        "operator_step",
        "ui_state",
        "next_action_possible",
    ]
    return [key for key in required if not event.ui_evidence.get(key)]


def redact_text(value: str | None) -> str | None:
    if value is None:
        return None

    redacted = value
    for pattern in SECRET_PATTERNS:
        redacted = pattern.sub(redact_match, redacted)
    return redacted


def redact_match(match: re.Match) -> str:
    prefix = match.groupdict().get("prefix")
    if prefix:
        return f"{prefix}[REDACTED]"
    return "Bearer [REDACTED]"


def redact_evidence_map(evidence: dict[str, str]) -> dict[str, str]:
    return {key: redact_text(value) or "" for key, value in evidence.items()}


def build_incident_log(event: IncidentEvent, policy: IncidentPolicy) -> dict:
    decision = decide_action(event, policy)
    missing_ui_evidence = validate_ui_evidence(event)
    valid = not missing_ui_evidence
    next_approval_boundary = (
        "continue"
        if decision["decision"].startswith("auto_allowed") and valid
        else "ask_user"
    )

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "phase": event.phase,
        "mode": policy.mode,
        "monitored_workflow": event.monitored_workflow,
        "trigger": event.trigger,
        "symptom": event.symptom,
        "impact": event.impact,
        "severity": event.severity,
        "action": event.action,
        "action_class": decision["action_class"],
        "decision": decision["decision"],
        "decision_reason": decision["reason"],
        "exact_automatic_action": (
            event.action if decision["decision"].startswith("auto_allowed") else None
        ),
        "valid": valid,
        "missing_ui_evidence": missing_ui_evidence,
        "evidence": {
            "pre_action": redact_text(event.pre_evidence),
            "post_action": redact_text(event.post_evidence),
            "sandbox": redact_text(event.sandbox_evidence),
            "real_network": redact_text(event.real_network_evidence),
            "ui": redact_evidence_map(event.ui_evidence),
        },
        "reporting": {
            "heartbeat_interval_seconds": policy.heartbeat_interval_seconds,
            "quiet_interval_seconds": policy.quiet_interval_seconds,
            "incident_escalation_interval_seconds": (
                policy.incident_escalation_interval_seconds
            ),
        },
        "next_approval_boundary": next_approval_boundary,
        "remaining_risk": redact_text(event.remaining_risk),
    }


def build_status_report(
    phase: str,
    monitored_surface: str,
    last_successful_check: str,
    active_incident_count: int,
    automatic_actions_taken: list[str],
    blocked_or_approval_actions: list[str],
    next_check: str,
    policy: IncidentPolicy,
    ui_status: dict[str, str] | None = None,
) -> dict:
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "phase": phase,
        "monitored_surface": monitored_surface,
        "last_successful_check": last_successful_check,
        "active_incident_count": active_incident_count,
        "automatic_actions_taken": automatic_actions_taken,
        "blocked_or_approval_actions": blocked_or_approval_actions,
        "next_check": next_check,
        "reporting": {
            "heartbeat_interval_seconds": policy.heartbeat_interval_seconds,
            "quiet_interval_seconds": policy.quiet_interval_seconds,
            "incident_escalation_interval_seconds": (
                policy.incident_escalation_interval_seconds
            ),
        },
    }
    if ui_status is not None:
        report["ui_status"] = redact_evidence_map(ui_status)
    return report
