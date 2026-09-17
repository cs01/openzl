#!/usr/bin/env python3
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.


"""
Pure renderer for SpecKit pipeline progress diagrams.
Reads JSON state from stdin, outputs ANSI diagram to stdout.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import TypedDict


# ANSI color codes
GREEN = "\033[32m"
YELLOW = "\033[33m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"


def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes from text for width calculation."""
    return re.sub(r"\033\[[0-9;]+m", "", text)


def should_use_color():
    """Check if ANSI colors should be used."""
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("TERM") == "dumb":
        return False
    return True


def colorize(text, color_code):
    """Wrap text in ANSI color code if colors are enabled."""
    if should_use_color():
        return f"{color_code}{text}{RESET}"
    return text


def add_border(content: str) -> str:
    """Wrap content in a light box-drawing border for visual emphasis."""
    lines = content.split("\n")
    max_width = max(len(strip_ansi(line)) for line in lines)

    # Border characters (colorize handles color detection internally)
    border = {char: colorize(char, DIM) for char in "┌┐└┘─│"}

    # Build top and bottom borders
    horizontal_line = border["─"] * (max_width + 2)
    top = f"{border['┌']}{horizontal_line}{border['┐']}"
    bottom = f"{border['└']}{horizontal_line}{border['┘']}"

    # Build content lines with side borders
    bordered_lines = [top]
    for line in lines:
        visual_len = len(strip_ansi(line))
        padding = " " * (max_width - visual_len)
        bordered_lines.append(f"{border['│']} {line}{padding} {border['│']}")
    bordered_lines.append(bottom)

    return "\n".join(bordered_lines)


class Transition(TypedDict):
    choices: list[str]
    recommended: str | None


# Pipeline sequences
GREENFIELD_SEQUENCE = [
    "specify",
    "clarify",
    "review",
    "plan",
    "tasks",
    "analyze",
    "implement",
    "verify",
]

BROWNFIELD_SEQUENCE = ["scan", "generate"]

# Transition maps for branching diagrams
GREENFIELD_TRANSITIONS: dict[str, Transition] = {
    "specify": {"choices": ["clarify", "review", "plan"], "recommended": "clarify"},
    "clarify": {"choices": ["review", "plan"], "recommended": "review"},
    "review": {"choices": ["plan"], "recommended": "plan"},
    "plan": {"choices": ["review", "tasks"], "recommended": None},  # dynamic
    "tasks": {"choices": ["analyze", "implement"], "recommended": "analyze"},
    "implement": {"choices": ["verify", "done"], "recommended": "verify"},
    "verify": {"choices": [], "recommended": None},
}

BROWNFIELD_TRANSITIONS: dict[str, Transition] = {
    "scan": {"choices": ["generate"], "recommended": "generate"},
    "generate": {"choices": ["clarify", "plan"], "recommended": "clarify"},
}


def determine_skipped_steps(state):
    """
    Determine which optional steps were skipped.
    A step is skipped if its artifact is missing AND we're past that step in the pipeline.
    """
    artifacts = state["artifacts"]
    pipeline = state["pipeline"]
    current_step = state["current_step"]

    if pipeline == "greenfield":
        sequence = GREENFIELD_SEQUENCE
        mandatory = {"specify", "plan", "tasks", "implement"}
    else:
        sequence = BROWNFIELD_SEQUENCE
        mandatory = {"scan", "generate"}

    skipped = set()
    past_current_step = False

    # Walk backwards from current step to find gaps
    for step in reversed(sequence):
        if step == current_step:
            past_current_step = True
            continue

        if past_current_step:
            # We're before the current step - check if this step was skipped
            if not artifacts.get(step, False) and step not in mandatory:
                skipped.add(step)

    return skipped


def render_linear_diagram(state):
    """Render linear diagram for 'running' status."""
    current_step = state["current_step"]
    artifacts = state["artifacts"]
    pipeline = state["pipeline"]

    sequence = GREENFIELD_SEQUENCE if pipeline == "greenfield" else BROWNFIELD_SEQUENCE
    skipped = determine_skipped_steps(state)

    parts = []
    for step in sequence:
        if artifacts.get(step, False):
            parts.append(colorize(f"✓ {step}", GREEN))
        elif step == current_step:
            parts.append(colorize(f"● {step}", BOLD))
        elif step in skipped:
            parts.append(colorize(f"- {step} -", DIM))
        else:
            parts.append(colorize(step, DIM))

    diagram = "  " + " ──▶ ".join(parts)

    # Align ▲ under the current (●) step
    plain = strip_ansi(diagram)
    pos = plain.find("●")
    if pos >= 0:
        arrow_indent = " " * pos
    else:
        arrow_indent = "  "
    diagram += f"\n{arrow_indent}{colorize('▲ running', DIM)}"

    return add_border(diagram)


def render_complete_diagram(state):
    """Render branching diagram for 'complete' status."""
    current_step = state["current_step"]
    artifacts = state["artifacts"]
    pipeline = state["pipeline"]
    context = state["context"]

    sequence = GREENFIELD_SEQUENCE if pipeline == "greenfield" else BROWNFIELD_SEQUENCE
    transitions = (
        GREENFIELD_TRANSITIONS if pipeline == "greenfield" else BROWNFIELD_TRANSITIONS
    )
    skipped = determine_skipped_steps(state)

    # Build completed portion (up to current step)
    parts = []
    for step in sequence:
        if step == current_step:
            parts.append(colorize(f"✓ {step}", GREEN))
            break
        elif artifacts.get(step, False):
            parts.append(colorize(f"✓ {step}", GREEN))
        elif step in skipped:
            parts.append(colorize(f"- {step} -", DIM))

    diagram = "  " + " ──▶ ".join(parts)

    # Terminal step (verify only)
    if current_step == "verify":
        diagram += f"\n{colorize('  ▲ done', DIM)}\n  Pipeline complete."
        return add_border(diagram)

    # Add branching choices
    if current_step in transitions:
        trans = transitions[current_step]
        choices = trans["choices"]
        recommended = trans["recommended"]

        # Dynamic recommendation for plan step
        if current_step == "plan" and recommended is None:
            risk = context.get("risk", "unknown")
            phase_count = context.get("phase_count", 0)
            if risk == "high" or phase_count >= 3:
                recommended = "review"
            else:
                recommended = "tasks"

        if len(choices) == 1:
            # Single choice - no branching tree
            next_cmd = choices[0]
            diagram += f" ──▶ {colorize(next_cmd, BOLD)} (next)"
        else:
            # Multiple choices - branching tree
            # Calculate indent to align branch under the current (last completed) step
            plain_diagram = strip_ansi(diagram)
            indent_len = len(plain_diagram) - len(plain_diagram.lstrip())
            # Find the position of the last step name in the line
            last_step_pos = plain_diagram.rfind(f"✓ {current_step}")
            if last_step_pos >= 0:
                branch_indent = " " * (last_step_pos + 2)
            else:
                branch_indent = "      "

            diagram += f"\n{branch_indent}│"
            for i, choice in enumerate(choices):
                is_last = i == len(choices) - 1
                connector = "└──▶" if is_last else "├──▶"

                if choice == recommended:
                    choice_text = colorize(choice, BOLD)
                    suffix = " (recommended)"
                else:
                    choice_text = colorize(choice, YELLOW)
                    suffix = ""

                diagram += f"\n{branch_indent}{connector} {choice_text}{suffix}"

        # Add copy-pasteable command
        if recommended and recommended != "done":
            diagram += f"\n\n  ▶ /speckit-{recommended}"
        elif choices and choices[0] != "done":
            diagram += f"\n\n  ▶ /speckit-{choices[0]}"

    return add_border(diagram)


def main():
    """Main entry point."""
    # Read JSON from stdin
    state = json.load(sys.stdin)

    # Render appropriate diagram
    if state["status"] == "running":
        diagram = render_linear_diagram(state)
    else:
        diagram = render_complete_diagram(state)

    print(diagram)


if __name__ == "__main__":
    main()
