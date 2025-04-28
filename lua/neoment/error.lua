local M = {}

--- @class neoment.Error<A, E>: { data?: A, error?: E }

--- Create a new Error instance.
--- @generic A
--- @generic E
--- @param error E The error
--- @return neoment.Error<A, E>
M.error = function(error)
	return {
		error = error,
	}
end

--- Create a new Ok instance.
--- @generic A, E
--- @param data A The data
--- @return neoment.Error<A, E>
M.ok = function(data)
	return {
		data = data,
	}
end

--- Check if the value is an error.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to check
--- @return boolean True if the value is an error, false otherwise
M.is_error = function(value)
	return value.error ~= nil
end

--- Check if the value is ok.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to check
--- @return boolean True if the value is ok, false otherwise
M.is_ok = function(value)
	return value.error == nil
end

--- Map a function over the value if it is ok.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to map over
--- @param fn fun(a: A): B The function to apply to the value
--- @return neoment.Error<B, E> The result of applying the function to the value
M.map = function(value, fn)
	if M.is_error(value) then
		return value
	end

	return M.ok(fn(value.data))
end

--- Map a function over the error if it is an error.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to map over
--- @param fn fun(e: E): B The function to apply to the error
--- @return neoment.Error<A, B> The result of applying the function to the error
M.map_error = function(value, fn)
	if M.is_ok(value) then
		return value
	end

	return M.error(fn(value.error))
end

--- Map a function that returns an Error over the value if it is ok.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to map over
--- @param fn fun(a: A): neoment.Error<B, E> The function to apply to the value
--- @return neoment.Error<B, E> The result of applying the function to the value
M.try = function(value, fn)
	if M.is_error(value) then
		return value
	end

	return fn(value.data)
end

--- Extract the value from the Error if it is ok, otherwise return the default value.
--- @generic A, E
--- @param value neoment.Error<A, E> The value to extract from
--- @param default A The default value to return if the value is an error
--- @return A The extracted value or the default value
M.unwrap = function(value, default)
	if M.is_error(value) then
		return default
	end

	return value.data
end

--- Match on the value, calling the appropriate function based on whether it is ok or an error.
--- @generic A, B, E
--- @param value neoment.Error<A, E> The value to match on
--- @param ok_fn fun(a: A): B The function to call if the value is ok
--- @param error_fn fun(e: E): B The function to call if the value is an error
--- @return B The result of calling the appropriate function
M.match = function(value, ok_fn, error_fn)
	if M.is_error(value) then
		return error_fn(value.error)
	end

	return ok_fn(value.data)
end

return M
