// Two tests on one line, and a suite chain collapsed onto one line. Line
// numbers say nothing about nesting here: `first` and `second` are siblings that
// share every line they occupy, and `beta`/`gamma`/`third` all start and end on
// the same one. Only the cursor column and the syntax tree can tell them apart.
describe('alpha', () => { it('first', () => { expect(1).toBe(1); }); it('second', () => { expect(2).toBe(2); }); });
describe('beta', () => { describe('gamma', () => { it('third', () => { expect(3).toBe(3); }); }); });
