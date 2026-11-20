describe("matrix push rules", function()
	local HOMESERVER = "https://example.org"
	local RULES_URL = HOMESERVER .. "/_matrix/client/v3/pushrules/global/"

	local client
	local matrix
	local api
	local error
	local requests
	local responses

	--- Record each authed request and answer it with the next queued response, or an empty success
	--- @param method string
	--- @return function
	local function recorder(method)
		return function(url, ...)
			local args = { ... }
			local callback = table.remove(args)
			table.insert(requests, { method = method, url = url, body = args[1] })
			callback(table.remove(responses, 1) or error.ok({}))
		end
	end

	before_each(function()
		for _, module in ipairs({ "neoment.matrix", "neoment.matrix.client", "neoment.matrix.api" }) do
			package.loaded[module] = nil
		end
		package.loaded["neoment.curl"] = {}
		package.loaded["neoment.rooms"] = { update_room_list = function() end }
		package.loaded["neoment.notify"] = {
			desktop_message = function() end,
			room_counts_changed = function() end,
			clear_candidates = function() end,
		}

		error = require("neoment.error")
		api = require("neoment.matrix.api")
		client = require("neoment.matrix.client")
		client.new(HOMESERVER, "token123")
		client.client.user_id = "@me:example.org"
		matrix = require("neoment.matrix")

		requests = {}
		responses = {}
		api.authed.get = recorder("GET")
		api.authed.put = function(url, body, callback)
			recorder("PUT")(url, body, callback)
		end
		api.authed.delete = recorder("DELETE")
	end)

	after_each(function()
		for _, module in ipairs({
			"neoment.matrix",
			"neoment.matrix.client",
			"neoment.matrix.api",
			"neoment.curl",
			"neoment.rooms",
			"neoment.notify",
		}) do
			package.loaded[module] = nil
		end
	end)

	describe("requests", function()
		it("fetches the push rules and stores them", function()
			local ruleset = { global = { override = {}, underride = {} } }
			responses = { error.ok(ruleset) }

			local result
			matrix.fetch_push_rules(function(r)
				result = r
			end)

			assert.are.same({ { method = "GET", url = HOMESERVER .. "/_matrix/client/v3/pushrules/" } }, requests)
			assert.are.same(ruleset, result.data)
			assert.are.same(ruleset, matrix.get_push_rules())
		end)

		it("reports a failed fetch without storing anything", function()
			responses = { error.err({ error = "Forbidden" }) }

			local result
			matrix.fetch_push_rules(function(r)
				result = r
			end)

			assert.is_true(error.is_error(result))
			assert.is_nil(matrix.get_push_rules())
		end)

		it("creates a rule with an encoded room ID", function()
			local body = { actions = { "notify" } }

			matrix.set_push_rule("room", "!room:server", body, function() end)

			assert.are.same({ { method = "PUT", url = RULES_URL .. "room/%21room%3Aserver", body = body } }, requests)
		end)

		it("deletes a rule with an encoded room ID", function()
			matrix.delete_push_rule("override", "!room:server", function() end)

			assert.are.same({ { method = "DELETE", url = RULES_URL .. "override/%21room%3Aserver" } }, requests)
		end)

		it("sets the actions of a rule", function()
			matrix.set_push_rule_actions("underride", ".m.rule.message", { "notify" }, function() end)

			assert.are.same({
				{
					method = "PUT",
					url = RULES_URL .. "underride/.m.rule.message/actions",
					body = { actions = { "notify" } },
				},
			}, requests)
		end)

		it("enables or disables a rule", function()
			matrix.set_push_rule_enabled("underride", ".m.rule.encrypted", false, function() end)

			assert.are.same({
				{
					method = "PUT",
					url = RULES_URL .. "underride/.m.rule.encrypted/enabled",
					body = { enabled = false },
				},
			}, requests)
		end)

		it("passes request errors to the callback", function()
			responses = { error.err({ error = "Not found", status = 404 }) }

			local result
			matrix.delete_push_rule("room", "!room:server", function(r)
				result = r
			end)

			assert.is_true(error.is_error(result))
		end)
	end)

	describe("sync", function()
		it("replaces the stored rules when a sync delivers them", function()
			client.client.push_rules = { global = { override = { { rule_id = "old" } } } }
			client.client.sync_token = "since"
			local ruleset = { global = { override = { { rule_id = "new" } } } }
			responses = {
				error.ok({
					next_batch = "next",
					account_data = { events = { { type = "m.push_rules", content = ruleset } } },
				}),
			}

			local done = false
			matrix.sync({}, function()
				done = true
			end)
			vim.wait(100, function()
				return done
			end)

			assert.is_true(done)
			assert.are.same(ruleset, matrix.get_push_rules())
		end)

		it("drops the rules when the homeserver changes", function()
			client.client.push_rules = { global = {} }

			matrix.set_homeserver(HOMESERVER)

			assert.is_nil(matrix.get_push_rules())
		end)
	end)
end)
