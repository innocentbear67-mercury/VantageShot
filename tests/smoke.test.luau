-- Harness smoke test: proves the Lune runner works end-to-end before real
-- property tests land in Phase 4.
local function fib(n: number): number
	if n < 2 then
		return n
	end
	return fib(n - 1) + fib(n - 2)
end

assert(fib(10) == 55, "fib(10) should be 55")

return { passed = true }
