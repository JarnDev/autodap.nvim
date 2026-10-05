class TestCompact:
    # One-line bodies: the def starts and ends on the same row as its class's
    # other members, so the enclosing class has to come from the tree.
    def test_one(self): assert True
    def test_two(self): assert True


class TestOther:
    def test_one(self): assert True
