local M = {}

--- @class neoment.Error<A, E>: { data?: A, error?: E }
--- @field map fun(self: neoment.Error<A, E>, fn: fun(a: A): any): neoment.Error<any, E>
--- @field map_error fun(self: neoment.Error<A, E>, fn: fun(e: E): any): neoment.Error<A, any>
--- @field try fun(self: neoment.Error<A, E>, fn: fun(a: A): neoment.Error<any, E>): neoment.Error<any, E>
--- @field unwrap fun(self: neoment.Error<A, E>, default: A): A
--- @field match fun(self: neoment.Error<A, E>, ok_fn: fun(a: A): any, error_fn: fun(e: E): any): any
--- @field recover fun(self: neoment.Error<A, E>, fn: fun(e: E): neoment.Error<A, E>): neoment.Error<A, E>
--- @field is_error fun(self: neoment.Error<A, E>): boolean
--- @field is_ok fun(self: neoment.Error<A, E>): boolean

local Result = {}
Result.__index = Result

function Result:is_error()
	return self.error ~= nil
end

function Result:is_ok()
	return self.error == nil
end

function Result:map(fn)
	if self:is_error() then
		return self
	end
	return M.ok(fn(self.data))
end

function Result:map_error(fn)
	if self:is_ok() then
		return self
	end
	return M.err(fn(self.error))
end

function Result:try(fn)
	if self:is_error() then
		return self
	end
	return fn(self.data)
end

function Result:unwrap(default)
	if self:is_error() then
		return default
	end
	if self.data == nil then
		return default
	end
	return self.data
end

function Result:match(ok_fn, error_fn)
	if self:is_error() then
		return error_fn(self.error)
	end
	return ok_fn(self.data)
end

function Result:recover(fn)
	if self:is_ok() then
		return self
	end
	return fn(self.error)
end

--- Create a new Err instance.
--- @generic A, E
--- @param e E The error value
--- @return neoment.Error<A, E>
M.err = function(e)
	return setmetatable({ error = e }, Result)
end

--- Create a new Ok instance.
--- @generic A, E
--- @param data A The data
--- @return neoment.Error<A, E>
M.ok = function(data)
	return setmetatable({ data = data }, Result)
end

--- Check if the value is an error.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to check
--- @return boolean True if the value is an error, false otherwise
M.is_error = function(value)
	return value:is_error()
end

--- Check if the value is ok.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to check
--- @return boolean True if the value is ok, false otherwise
M.is_ok = function(value)
	return value:is_ok()
end

--- Map a function over the value if it is ok.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to map over
--- @param fn fun(a: A): B The function to apply to the value
--- @return neoment.Error<B, E> The result of applying the function to the value
M.map = function(value, fn)
	return value:map(fn)
end

--- Map a function over the error if it is an error.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to map over
--- @param fn fun(e: E): B The function to apply to the error
--- @return neoment.Error<A, B> The result of applying the function to the error
M.map_error = function(value, fn)
	return value:map_error(fn)
end

--- Map a function that returns an Error over the value if it is ok.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to map over
--- @param fn fun(a: A): neoment.Error<B, E> The function to apply to the value
--- @return neoment.Error<B, E> The result of applying the function to the value
M.try = function(value, fn)
	return value:try(fn)
end

--- Extract the value from the Error if it is ok, otherwise return the default value.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to extract from
--- @param default A The default value to return if the value is an error or nil
--- @return A The extracted value or the default value
M.unwrap = function(value, default)
	return value:unwrap(default)
end

--- Match on the value, calling the appropriate function based on whether it is ok or an error.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to match on
--- @param ok_fn fun(a: A): B The function to call if the value is ok
--- @param error_fn fun(e: E): B The function to call if the value is an error
--- @return B The result of calling the appropriate function
M.match = function(value, ok_fn, error_fn)
	return value:match(ok_fn, error_fn)
end

--- Recover from an error by applying a function that returns a new Error.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to recover from
--- @param fn fun(e: E): neoment.Error<A, E> The function to apply to the error
--- @return neoment.Error<A, E> The result of applying the function to the error, or the original value if ok
M.recover = function(value, fn)
	return value:recover(fn)
end

return M
