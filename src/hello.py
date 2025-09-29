"""Intentionally broken greeting helper used to trigger the repair workflow."""


def greet(name: str) -> str:
    """Return a friendly greeting for the provided name."""
    # Deliberately incorrect implementation so that pytest fails.
    return f"Hi there, {name}?"
