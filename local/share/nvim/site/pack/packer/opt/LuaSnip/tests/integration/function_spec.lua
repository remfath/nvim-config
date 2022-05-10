local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("FunctionNode", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Text generated on expand/general test of functionality.", function()
		local snip = [[
			s("trig", {
				f(function(args, snip)
					return "it expands"
				end, {})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "it expands" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			it expands^                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Updates when argnodes' text changes + args as table.", function()
		local snip = [[
			s("trig", {
				i(1, "a"), t" -> ", f(function(args) return args[1] end, 1), t" == ", f(function(args) return args[1] end, {1})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "a -> a == a" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^a -> a == a                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- does updating manually work?
		feed("b")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			b^ -> b == b                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- does updating by jumping work?
		feed("<BS>c")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			c -> c == c^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Text from functionNode is properly indented.", function()
		local snip = [[
			s("trig", {
				f(function() return {"multiline", "text"} end, {})
			})
		]]
		feed("i<Tab>")
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			        multiline                                 |
			        text^                                      |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Updates in choiceNode.", function()
		exec_lua([[
			local function func(args, snip)
				return args[1]
			end

			ls.snip_expand(s("trig", {
				i(1, "bbbb"),
				t" ",
				c(2, {
					t"aaaa",
					f(func, {1})
				})
			}))
		]])
		screen:expect({
			grid = [[
			^b{3:bbb} aaaa                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change text of argnode, shouldn't update fNode just yet.
		feed("cccc")
		screen:expect({
			grid = [[
			cccc^ aaaa                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- the update isn't visible...
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			cccc ^aaaa                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- now it is.
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			cccc ^cccc                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- make sure that updating while the fNode is the active choice
		-- actually updates it directly.
		exec_lua("ls.jump(-1)")
		feed("dddd")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			dddd^ dddd                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Updates after all argnodes become available.", function()
		local snip = [[
			s("trig", {
				i(1, "cccc"),
				t" ",
				c(2, {
					t"aaaa",
					i(nil, "bbbb")
				}),
				f(function(args) return args[1][1]..args[2][1] end, {ai[2][2], 1} )
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "cccc aaaa" }
		)
		-- the functionNode shouldn't be evaluated after expansion, the ai[2][2] isn't available.
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^c{3:ccc} aaaa                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change choice, the functionNode should now update.
		exec_lua("ls.jump(1)")
		exec_lua("ls.change_choice(1)")

		screen:expect({
			grid = [[
			cccc ^b{3:bbb}bbbbcccc                                 |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change choice once more, so the necessary choice isn't visible, jump back,
		-- change text and update -> should lead to no new evaluation.
		exec_lua("ls.change_choice(1)")
		exec_lua("ls.jump(-1)")
		feed("aaaa")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			aaaa^ aaaabbbbcccc                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- change choice once more, this time the fNode should be evaluated again.
		exec_lua("ls.jump(1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			aaaa ^b{3:bbb}bbbbaaaa                                 |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)
end)
