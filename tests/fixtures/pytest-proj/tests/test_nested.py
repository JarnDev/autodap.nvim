import pytest


class TestOuter:
    class TestInner:
        @pytest.mark.parametrize("n", [1, 2])
        def test_param(self, n):
            def test_helper():  # noqa: PT — deliberately shaped like a test
                # A def inside a test is not a test — pytest never collects it.
                return n

            assert test_helper() == n

    def test_outer_only(self):
        assert True


def test_module_level():
    assert True
