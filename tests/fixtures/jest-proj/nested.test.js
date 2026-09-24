describe('outer suite', () => {
  describe('inner suite', () => {
    it.only('adds (two) numbers', () => {
      expect(1 + 1).toBe(2);
    });

    it.each([[1, 2], [3, 4]])('adds %i and %i', (a, b) => {
      expect(a + b).toBeGreaterThan(0);
    });

    test(`interpolates ${'x'} in the title`, () => {
      expect(true).toBe(true);
    });
  });

  // Not inside any it(): the cursor here belongs to the outer suite.
  it('is only in the outer suite', () => {
    expect(1).toBe(1);
  });
});
