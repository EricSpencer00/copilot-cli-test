from src.hello import greet


def test_greet_returns_expected_string():
    assert greet("world") == "Hello, world!"
