local handler = require 'kong.plugins.signalfx.handler'
local helpers = require "spec.helpers"
local cjson = require "cjson"
local tostr = require 'pl.pretty'.write
local fmt = string.format


for _, strategy in helpers.each_strategy() do
  describe(fmt("Aggregation (%s)", strategy), function()

    local proxy_client, admin_client
    local service_one, route_one
    local service_two, route_two

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      service_one = bp.services:insert({})

      route_one = bp.routes:insert({
        hosts = { "myhost" },
        service = service_one
      })

      assert(bp.plugins:insert {
        name = "signalfx",
        route_id = route_one.id,
      })

      service_two = bp.services:insert({})

      route_two = bp.routes:insert({
        hosts = { "myotherhost" },
        service = service_two
      })

      assert(bp.plugins:insert {
        name = "signalfx",
        config = { aggregate_by_http_method = false },
        route_id = route_two.id,
      })

      assert(helpers.start_kong({
        path = os.getenv("PATH"),
        lua_package_path = os.getenv("LUA_PATH"),
        database = strategy,
        nginx_conf = "/opt/kong-plugin-signalfx/spec/custom_nginx.template",
        plugins = "signalfx"
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if proxy_client then proxy_client:close() end
      if admin_client then admin_client:close() end
      helpers.stop_kong()
    end)

    it("Aggregates as expected with http method", function()
      for i=1, 1000 do
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "myhost",
          }
        })
        assert.res_status(200, res)
      end
      ngx.sleep(1)
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/signalfx",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(json.database, {database_reachable = true})
      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.total_requests)
      local hdler = handler()
      local expected_message = { service = service_one, route = route_one, request = { method = 'GET' } }
      local expected_key = hdler:get_context_key(expected_message, { aggregate_by_http_method = true }):sub(6)
      local metric_val_string = json.signalfx[expected_key]
      assert.is_string(metric_val_string)
      local request_count, _, _, _, _, _, statuses = hdler:decode_metrics(metric_val_string)
      assert.is_equal(request_count, 1000)
      assert.is_equal(statuses["200"].count, 1000)
    end)

    it("Aggregates as expected without http method", function()
      for i=1, 1000 do
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "myotherhost",
          }
        })
        assert.res_status(200, res)
      end
      ngx.sleep(1)
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/signalfx",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(json.database, {database_reachable = true})
      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.total_requests)
      local hdler = handler()
      local expected_message = { service = service_two, route = route_two, request = {} }
      local expected_key = hdler:get_context_key(expected_message, { aggregate_by_http_method = false }):sub(6)
      local metric_val_string = json.signalfx[expected_key]
      assert.is_string(metric_val_string)
      local request_count, _, _, _, _, _, statuses = hdler:decode_metrics(metric_val_string)
      assert.is_equal(request_count, 1000)
      assert.is_equal(statuses["200"].count, 1000)
    end)
  end)
end
